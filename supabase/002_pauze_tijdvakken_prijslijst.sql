-- Nail Bar by Fran — update 002
-- Pauze tussen afspraken, starttijden op hele/halve uren, categorieën, extra's en de nieuwe prijslijst.
-- Plak dit in Supabase > SQL Editor > New query en klik Run.

-- 1. Instellingen (pauze + starttijden)
create table if not exists public.settings (
  id boolean primary key default true check (id),
  buffer_min int not null default 15 check (buffer_min between 0 and 120),
  slot_step_min int not null default 30 check (slot_step_min in (15, 30, 60))
);
insert into public.settings(id) values (true) on conflict do nothing;
alter table public.settings enable row level security;
drop policy if exists settings_read on public.settings;
drop policy if exists settings_admin on public.settings;
create policy settings_read on public.settings for select using (true);
create policy settings_admin on public.settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- 2. Categorieën en extra's
alter table public.services add column if not exists category text not null default 'Overig';
alter table public.services add column if not exists is_extra boolean not null default false;
alter table public.bookings add column if not exists extras text;

-- 3. Boekingslogica opnieuw (met extra's, pauze en tijdvakken)
drop function if exists public.get_available_dates(uuid, date, date);
drop function if exists public.get_slots(uuid, date);
drop function if exists public.create_booking(uuid, timestamptz, text, text, text, text);

create or replace function public.total_duration(p_service_id uuid, p_extras uuid[])
returns int language sql stable security definer set search_path = public as $$
  select s.duration_min + coalesce((select sum(e.duration_min) from services e
           where e.id = any(coalesce(p_extras,'{}')) and e.active and e.is_extra), 0)::int
  from services s where s.id = p_service_id and s.active and not s.is_extra;
$$;

create or replace function public.get_slots(p_service_id uuid, p_date date, p_extras uuid[] default '{}')
returns table(slot_start timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dur int; v_open time; v_close time; v_isopen boolean; v_buf interval; v_step interval;
  v_tz constant text := 'Europe/Amsterdam';
  v_today date := (now() at time zone 'Europe/Amsterdam')::date;
begin
  v_dur := total_duration(p_service_id, p_extras);
  if v_dur is null then return; end if;
  if p_date < v_today or p_date > v_today + 60 then return; end if;
  select make_interval(mins => buffer_min), make_interval(mins => slot_step_min) into v_buf, v_step from settings limit 1;
  v_buf := coalesce(v_buf, interval '0'); v_step := coalesce(v_step, interval '30 minutes');
  select h.is_open, h.open_time, h.close_time into v_isopen, v_open, v_close
    from opening_hours h where h.weekday = extract(isodow from p_date);
  if not coalesce(v_isopen, false) then return; end if;
  return query
  select x.t from (
    select (g at time zone v_tz) as t
    from generate_series(p_date + v_open, (p_date + v_close) - make_interval(mins => v_dur), v_step) g
  ) x
  where x.t >= now() + interval '2 hours'
    and not exists (select 1 from bookings b where b.status = 'confirmed'
                    and tstzrange(b.starts_at - v_buf, b.ends_at + v_buf) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
    and not exists (select 1 from blocks k
                    where tstzrange(k.starts_at, k.ends_at) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
  order by x.t;
end $$;

create or replace function public.get_available_dates(p_service_id uuid, p_from date, p_to date, p_extras uuid[] default '{}')
returns table(available_date date)
language sql stable security definer set search_path = public as $$
  select d::date from generate_series(p_from, least(p_to, p_from + 62), interval '1 day') d
  where exists (select 1 from public.get_slots(p_service_id, d::date, p_extras));
$$;

create or replace function public.create_booking(p_service_id uuid, p_starts_at timestamptz, p_name text, p_email text, p_phone text,
                                                 p_note text default null, p_extras uuid[] default '{}')
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_s services%rowtype; v_id uuid; v_tok uuid; v_end timestamptz; v_email text := lower(trim(p_email));
        v_dur int; v_price int; v_extras text;
begin
  select * into v_s from services s where s.id = p_service_id and s.active and not s.is_extra;
  if not found then raise exception 'Deze behandeling bestaat niet (meer).'; end if;
  if (select count(*) from bookings b where b.customer_email = v_email and b.status = 'confirmed' and b.starts_at > now()) >= 3 then
    raise exception 'Je hebt al 3 openstaande afspraken. Neem contact op voor meer afspraken.';
  end if;
  if not exists (select 1 from get_slots(p_service_id, (p_starts_at at time zone 'Europe/Amsterdam')::date, p_extras) g where g.slot_start = p_starts_at) then
    raise exception 'Dit tijdstip is helaas niet meer beschikbaar. Kies een ander moment.';
  end if;
  v_dur := total_duration(p_service_id, p_extras);
  select v_s.price_cents + coalesce(sum(e.price_cents),0), string_agg(e.name, ', ' order by e.sort)
    into v_price, v_extras from services e where e.id = any(coalesce(p_extras,'{}')) and e.active and e.is_extra;
  v_end := p_starts_at + make_interval(mins => v_dur);
  begin
    insert into bookings(service_id, service_name, price_cents, duration_min, starts_at, ends_at, customer_name, customer_email, customer_phone, note, extras)
    values (v_s.id, v_s.name, v_price, v_dur, p_starts_at, v_end, trim(p_name), v_email, trim(p_phone), nullif(trim(coalesce(p_note,'')), ''), v_extras)
    returning id, cancel_token into v_id, v_tok;
  exception when exclusion_violation then
    raise exception 'Dit tijdstip is net door iemand anders geboekt. Kies een ander moment.';
  end;
  return jsonb_build_object('id', v_id, 'cancel_token', v_tok, 'starts_at', p_starts_at, 'ends_at', v_end,
                            'service_name', v_s.name, 'extras', v_extras, 'price_cents', v_price);
end $$;

create or replace function public.get_booking(p_token uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('service_name', b.service_name || coalesce(' + ' || b.extras, ''), 'starts_at', b.starts_at, 'ends_at', b.ends_at,
                            'status', b.status, 'customer_name', b.customer_name, 'price_cents', b.price_cents,
                            'can_cancel', b.status = 'confirmed' and b.starts_at > now() + interval '24 hours')
  from public.bookings b where b.cancel_token = p_token;
$$;

revoke all on function public.total_duration(uuid, uuid[]) from public;
revoke all on function public.get_slots(uuid, date, uuid[]) from public;
revoke all on function public.get_available_dates(uuid, date, date, uuid[]) from public;
revoke all on function public.create_booking(uuid, timestamptz, text, text, text, text, uuid[]) from public;
grant execute on function public.total_duration(uuid, uuid[]) to anon, authenticated;
grant execute on function public.get_slots(uuid, date, uuid[]) to anon, authenticated;
grant execute on function public.get_available_dates(uuid, date, date, uuid[]) to anon, authenticated;
grant execute on function public.create_booking(uuid, timestamptz, text, text, text, text, uuid[]) to anon, authenticated;

-- 4. Afrekenen (contant/pin), niet gekomen, btw-tarief
alter table public.bookings add column if not exists payment_method text check (payment_method in ('contant','pin'));
alter table public.bookings add column if not exists paid_cents int check (paid_cents >= 0);
alter table public.bookings add column if not exists paid_at timestamptz;
alter table public.bookings drop constraint if exists bookings_status_check;
alter table public.bookings add constraint bookings_status_check check (status in ('confirmed','cancelled','no_show'));
alter table public.settings add column if not exists vat_rate numeric not null default 21 check (vat_rate between 0 and 30);

-- 5. Nieuwe prijslijst (oude behandelingen worden verwijderd, of offline gezet als er al afspraken aan hangen)
delete from public.services s where not exists (select 1 from public.bookings b where b.service_id = s.id);
update public.services set active = false, sort = 100 + sort;
insert into public.services(name, description, price_cents, duration_min, sort, category, is_extra) values
 ('BIAB Naturel', 'Versterkende BIAB-laag met een natuurlijke look.', 5000, 60, 1, 'BIAB natural nail treatment', false),
 ('BIAB Gel Colour', 'BIAB-versteviging met een gelkleur naar keuze.', 5500, 75, 2, 'BIAB natural nail treatment', false),
 ('BIAB French', 'BIAB-versteviging met een tijdloze French-afwerking.', 6000, 90, 3, 'BIAB natural nail treatment', false),
 ('Gel Colour', 'Gellak in een kleur naar keuze.', 3500, 60, 4, 'Gellak treatment', false),
 ('Removal without new product', 'Veilig verwijderen, zonder nieuwe set.', 2000, 30, 5, 'Extra''s', false),
 ('Nail Art Small', 'Kleine nail art als accent.', 500, 10, 6, 'Extra''s', true),
 ('French', 'French-afwerking bij je behandeling.', 1000, 15, 7, 'Extra''s', true),
 ('Removal other salon', 'Verwijderen van product van een andere salon.', 500, 15, 8, 'Extra''s', true);
