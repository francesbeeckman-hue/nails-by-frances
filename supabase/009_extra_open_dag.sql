-- Nail Bar by Fran — update 009: extra open dag (bijv. open op een dag waarop je normaal dicht bent)
-- Plak dit in Supabase > SQL Editor > New query en klik Run.

create table if not exists public.extra_open_days (
  day date primary key,
  open_time time not null,
  close_time time not null,
  check (close_time > open_time)
);
alter table public.extra_open_days enable row level security;
drop policy if exists extra_open_read on public.extra_open_days;
drop policy if exists extra_open_admin on public.extra_open_days;
create policy extra_open_read on public.extra_open_days for select using (true);
create policy extra_open_admin on public.extra_open_days for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.get_slots(p_service_id uuid, p_date date, p_extras uuid[] default '{}')
returns table(slot_start timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare
  v_dur int; v_open time; v_close time; v_isopen boolean; v_buf interval; v_step interval;
  v_ls time; v_le time; v_lunch tstzrange;
  v_tz constant text := 'Europe/Amsterdam';
  v_today date := (now() at time zone 'Europe/Amsterdam')::date;
begin
  v_dur := total_duration(p_service_id, p_extras);
  if v_dur is null then return; end if;
  if p_date < v_today or p_date > v_today + 366 then return; end if;
  select make_interval(mins => buffer_min), make_interval(mins => slot_step_min), lunch_start, lunch_end
    into v_buf, v_step, v_ls, v_le from settings limit 1;
  v_buf := coalesce(v_buf, interval '0'); v_step := coalesce(v_step, interval '30 minutes');
  if v_ls is not null and v_le is not null and v_le > v_ls then
    v_lunch := tstzrange((p_date + v_ls) at time zone v_tz, (p_date + v_le) at time zone v_tz);
  end if;
  select h.is_open, h.open_time, h.close_time into v_isopen, v_open, v_close
    from opening_hours h where h.weekday = extract(isodow from p_date);
  -- extra open dag gaat voor de vaste week
  if exists (select 1 from extra_open_days x where x.day = p_date) then
    select true, x.open_time, x.close_time into v_isopen, v_open, v_close from extra_open_days x where x.day = p_date;
  end if;
  if not coalesce(v_isopen, false) then return; end if;
  return query
  select x.t from (
    select (g at time zone v_tz) as t
    from generate_series(p_date + v_open, (p_date + v_close) - make_interval(mins => v_dur), v_step) g
  ) x
  where x.t >= now() + interval '2 hours'
    and (v_lunch is null or not (v_lunch && tstzrange(x.t, x.t + make_interval(mins => v_dur))))
    and not exists (select 1 from bookings b where b.status = 'confirmed'
                    and tstzrange(b.starts_at - v_buf, b.ends_at + v_buf) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
    and not exists (select 1 from blocks k
                    where tstzrange(k.starts_at, k.ends_at) && tstzrange(x.t, x.t + make_interval(mins => v_dur)))
  order by x.t;
end $$;
