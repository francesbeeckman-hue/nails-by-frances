-- Nail Bar by Fran: pauze tussen afspraken + tijdvakken (instelbaar in beheer)
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

create or replace function public.get_slots(p_service_id uuid, p_date date)
returns table(slot_start timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dur int; v_open time; v_close time; v_isopen boolean;
  v_buf interval; v_step interval;
  v_tz constant text := 'Europe/Amsterdam';
  v_today date := (now() at time zone 'Europe/Amsterdam')::date;
begin
  select s.duration_min into v_dur from services s where s.id = p_service_id and s.active;
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

revoke all on function public.get_slots(uuid, date) from public;
grant execute on function public.get_slots(uuid, date) to anon, authenticated;
