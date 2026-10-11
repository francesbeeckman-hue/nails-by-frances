-- Nails by Frances: complete database-setup
-- Plak dit in Supabase > SQL Editor > New query en klik Run.

create extension if not exists btree_gist with schema extensions;

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null, description text,
  price_cents int not null check (price_cents >= 0),
  duration_min int not null check (duration_min between 5 and 480),
  active boolean not null default true, sort int not null default 0,
  created_at timestamptz not null default now());

create table public.opening_hours (
  weekday smallint primary key check (weekday between 1 and 7),
  is_open boolean not null default false,
  open_time time not null default '09:00', close_time time not null default '17:00',
  check (close_time > open_time));

create table public.blocks (
  id uuid primary key default gen_random_uuid(),
  starts_at timestamptz not null, ends_at timestamptz not null, reason text,
  created_at timestamptz not null default now(), check (ends_at > starts_at));
create index blocks_starts_idx on public.blocks(starts_at);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services(id),
  service_name text not null, price_cents int not null, duration_min int not null,
  starts_at timestamptz not null, ends_at timestamptz not null,
  customer_name text not null check (length(customer_name) between 2 and 100),
  customer_email text not null check (customer_email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  customer_phone text not null check (length(customer_phone) between 6 and 30),
  note text check (note is null or length(note) <= 1000),
  status text not null default 'confirmed' check (status in ('confirmed','cancelled')),
  cancel_token uuid not null default gen_random_uuid() unique,
  source text not null default 'online' check (source in ('online','admin')),
  created_at timestamptz not null default now(), cancelled_at timestamptz,
  check (ends_at > starts_at),
  constraint bookings_no_overlap exclude using gist (tstzrange(starts_at, ends_at) with &&) where (status = 'confirmed'));
create index bookings_starts_idx on public.bookings(starts_at);
create index bookings_email_idx on public.bookings(customer_email);

create table public.admins (email text primary key);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins a where lower(a.email) = lower(coalesce(auth.jwt()->>'email','')));
$$;

alter table public.services enable row level security;
alter table public.opening_hours enable row level security;
alter table public.blocks enable row level security;
alter table public.bookings enable row level security;
alter table public.admins enable row level security;

create policy services_read on public.services for select using (active or public.is_admin());
create policy services_admin on public.services for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy hours_read on public.opening_hours for select using (true);
create policy hours_admin on public.opening_hours for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy blocks_admin on public.blocks for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy bookings_admin on public.bookings for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.get_slots(p_service_id uuid, p_date date)
returns table(slot_start timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dur int; v_open time; v_close time; v_isopen boolean;
  v_tz constant text := 'Europe/Amsterdam';
  v_today date := (now() at time zone 'Europe/Amsterdam')::date;
begin
  select s.duration_min into v_dur from services s where s.id = p_service_id and s.active;
  if v_dur is null then return; end if;
  if p_date < v_today or p_date > v_today + 60 then return; end if;
  select h.is_open, h.open_time, h.close_time into v_isopen, v_open, v_close
    from opening_hours h where h.weekday = extract(isodow from p_date);
  if not coalesce(v_isopen, false) then return; end if;
  return query
  select x.t from (
    select (g at time zone v_tz) as t
    from generate_series(p_date + v_open, (p_date + v_close) - make_interval(mins => v_dur), interval '15 minutes') g
  ) x
  where x.t >= now() + interval '2 hours'
    and not exists (select 1 from bookings b where b.status = 'confirmed'
                    and tstzrange(b.starts_at, b.ends_at) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
    and not exists (select 1 from blocks k
                    where tstzrange(k.starts_at, k.ends_at) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
  order by x.t;
end $$;

create or replace function public.get_available_dates(p_service_id uuid, p_from date, p_to date)
returns table(available_date date)
language sql stable security definer set search_path = public as $$
  select d::date from generate_series(p_from, least(p_to, p_from + 62), interval '1 day') d
  where exists (select 1 from public.get_slots(p_service_id, d::date));
$$;

create or replace function public.create_booking(p_service_id uuid, p_starts_at timestamptz, p_name text, p_email text, p_phone text, p_note text default null)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_s services%rowtype; v_id uuid; v_tok uuid; v_end timestamptz; v_email text := lower(trim(p_email));
begin
  select * into v_s from services s where s.id = p_service_id and s.active;
  if not found then raise exception 'Deze behandeling bestaat niet (meer).'; end if;
  if (select count(*) from bookings b where b.customer_email = v_email and b.status = 'confirmed' and b.starts_at > now()) >= 3 then
    raise exception 'Je hebt al 3 openstaande afspraken. Neem contact op voor meer afspraken.';
  end if;
  if not exists (select 1 from get_slots(p_service_id, (p_starts_at at time zone 'Europe/Amsterdam')::date) g where g.slot_start = p_starts_at) then
    raise exception 'Dit tijdstip is helaas niet meer beschikbaar. Kies een ander moment.';
  end if;
  v_end := p_starts_at + make_interval(mins => v_s.duration_min);
  begin
    insert into bookings(service_id, service_name, price_cents, duration_min, starts_at, ends_at, customer_name, customer_email, customer_phone, note)
    values (v_s.id, v_s.name, v_s.price_cents, v_s.duration_min, p_starts_at, v_end, trim(p_name), v_email, trim(p_phone), nullif(trim(coalesce(p_note,'')), ''))
    returning id, cancel_token into v_id, v_tok;
  exception when exclusion_violation then
    raise exception 'Dit tijdstip is net door iemand anders geboekt. Kies een ander moment.';
  end;
  return jsonb_build_object('id', v_id, 'cancel_token', v_tok, 'starts_at', p_starts_at, 'ends_at', v_end,
                            'service_name', v_s.name, 'price_cents', v_s.price_cents);
end $$;

create or replace function public.get_booking(p_token uuid)
returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('service_name', b.service_name, 'starts_at', b.starts_at, 'ends_at', b.ends_at,
                            'status', b.status, 'customer_name', b.customer_name, 'price_cents', b.price_cents,
                            'can_cancel', b.status = 'confirmed' and b.starts_at > now() + interval '24 hours')
  from public.bookings b where b.cancel_token = p_token;
$$;

create or replace function public.cancel_booking(p_token uuid)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare v_b bookings%rowtype;
begin
  select * into v_b from bookings b where b.cancel_token = p_token for update;
  if not found then raise exception 'Afspraak niet gevonden.'; end if;
  if v_b.status = 'cancelled' then raise exception 'Deze afspraak is al geannuleerd.'; end if;
  if v_b.starts_at <= now() + interval '24 hours' then
    raise exception 'Annuleren kan online tot 24 uur van tevoren. Neem contact op met Frances.';
  end if;
  update bookings set status = 'cancelled', cancelled_at = now() where id = v_b.id;
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.get_slots(uuid, date) from public;
revoke all on function public.get_available_dates(uuid, date, date) from public;
revoke all on function public.create_booking(uuid, timestamptz, text, text, text, text) from public;
revoke all on function public.get_booking(uuid) from public;
revoke all on function public.cancel_booking(uuid) from public;
grant execute on function public.get_slots(uuid, date) to anon, authenticated;
grant execute on function public.get_available_dates(uuid, date, date) to anon, authenticated;
grant execute on function public.create_booking(uuid, timestamptz, text, text, text, text) to anon, authenticated;
grant execute on function public.get_booking(uuid) to anon, authenticated;
grant execute on function public.cancel_booking(uuid) to anon, authenticated;

insert into public.opening_hours(weekday, is_open, open_time, close_time) values
 (1,true,'09:00','17:00'),(2,true,'09:00','17:00'),(3,true,'09:00','17:00'),
 (4,true,'09:00','17:00'),(5,true,'09:00','17:00'),(6,false,'09:00','17:00'),(7,false,'09:00','17:00');

insert into public.services(name, description, price_cents, duration_min, sort) values
 ('Gellak handen', 'Verzorgde nagels met een glanzende gellak die weken mooi blijft.', 3500, 60, 1),
 ('BIAB nieuwe set', 'Builder in a bottle voor sterke, natuurlijke nagels.', 5000, 75, 2),
 ('BIAB opvullen', 'Onderhoud van je BIAB-set, inclusief nieuwe kleur.', 4500, 75, 3),
 ('Gelnagels nieuwe set', 'Verlenging met gel in de lengte en vorm die jij wilt.', 6000, 105, 4),
 ('Gelnagels opvullen', 'Opvullen van je gelnagels, inclusief nieuwe kleur.', 4500, 90, 5),
 ('Manicure', 'Nagels vijlen, nagelriemen verzorgen en een verzorgende finish.', 3000, 45, 6),
 ('Gellak voeten', 'Gellak op je teennagels voor perfecte voeten.', 3500, 60, 7),
 ('Verwijderen', 'Veilig verwijderen van gellak, BIAB of gelnagels.', 1500, 30, 8);

-- Beheer-login voor Frances
do $$
declare uid uuid := gen_random_uuid(); em text := 'admin@nailsbyfrances.nl';
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
    extensions.crypt('Frances-PbXAtCitxZ', extensions.gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
  insert into public.admins(email) values (em);
end $$;
