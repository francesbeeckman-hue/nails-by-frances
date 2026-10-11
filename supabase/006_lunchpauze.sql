-- Nail Bar by Fran — update 006
-- Vaste lunchpauze (standaard 12:30–13:00). Aan te passen of uit te zetten in beheer > Openingstijden & planning.
-- Plak dit in Supabase > SQL Editor > New query en klik Run.

alter table public.settings add column if not exists lunch_start time default '12:30';
alter table public.settings add column if not exists lunch_end   time default '13:00';
update public.settings set lunch_start = '12:30', lunch_end = '13:00' where lunch_start is null and lunch_end is null;

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
  if p_date < v_today or p_date > v_today + 60 then return; end if;
  select make_interval(mins => buffer_min), make_interval(mins => slot_step_min), lunch_start, lunch_end
    into v_buf, v_step, v_ls, v_le from settings limit 1;
  v_buf := coalesce(v_buf, interval '0'); v_step := coalesce(v_step, interval '30 minutes');
  if v_ls is not null and v_le is not null and v_le > v_ls then
    v_lunch := tstzrange((p_date + v_ls) at time zone v_tz, (p_date + v_le) at time zone v_tz);
  end if;
  select h.is_open, h.open_time, h.close_time into v_isopen, v_open, v_close
    from opening_hours h where h.weekday = extract(isodow from p_date);
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
