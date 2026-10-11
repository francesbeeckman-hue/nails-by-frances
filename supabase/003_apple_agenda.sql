-- Nail Bar by Fran — update 003: agenda-link voor Apple Agenda / Google Agenda
-- Plak dit (na update 002) in Supabase > SQL Editor > New query en klik Run.

create table if not exists public.private_settings (
  id boolean primary key default true check (id),
  calendar_token uuid not null default gen_random_uuid()
);
insert into public.private_settings(id) values (true) on conflict do nothing;
alter table public.private_settings enable row level security;
drop policy if exists private_settings_admin on public.private_settings;
create policy private_settings_admin on public.private_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.ics_escape(t text) returns text language sql immutable as $$
  select replace(replace(replace(replace(coalesce(t,''), '\', '\\'), ';', '\;'), ',', '\,'), E'\n', '\n');
$$;

create or replace function public.calendar_feed(p_token uuid)
returns text
language plpgsql stable security definer set search_path = public as $$
declare v text; r record; nl constant text := E'\r\n';
  f constant text := 'YYYYMMDD"T"HH24MISS"Z"';
begin
  if p_token is null or not exists (select 1 from private_settings where calendar_token = p_token) then
    raise exception 'Ongeldige agenda-link';
  end if;
  v := 'BEGIN:VCALENDAR' || nl || 'VERSION:2.0' || nl || 'PRODID:-//Nail Bar by Fran//Agenda//NL' || nl ||
       'CALSCALE:GREGORIAN' || nl || 'METHOD:PUBLISH' || nl || 'X-WR-CALNAME:Nail Bar by Fran' || nl ||
       'X-WR-TIMEZONE:Europe/Amsterdam' || nl || 'REFRESH-INTERVAL;VALUE=DURATION:PT15M' || nl || 'X-PUBLISHED-TTL:PT15M' || nl;
  for r in select * from bookings where status = 'confirmed' and starts_at > now() - interval '90 days' order by starts_at loop
    v := v || 'BEGIN:VEVENT' || nl ||
      'UID:' || r.id || '@nailbarbyfran' || nl ||
      'DTSTAMP:' || to_char(coalesce(r.paid_at, r.created_at) at time zone 'UTC', f) || nl ||
      'DTSTART:' || to_char(r.starts_at at time zone 'UTC', f) || nl ||
      'DTEND:' || to_char(r.ends_at at time zone 'UTC', f) || nl ||
      'SUMMARY:' || ics_escape(r.customer_name || ' · ' || r.service_name || coalesce(' + ' || replace(r.extras, ', ', ' + '), '')) || nl ||
      'DESCRIPTION:' || ics_escape(
          'Tel: ' || r.customer_phone ||
          case when r.customer_email like '%@nailsbyfrances.nl' or r.customer_email like '%@nailbarbyfran.nl' then '' else E'\nE-mail: ' || r.customer_email end ||
          E'\nPrijs: €' || replace(to_char(r.price_cents / 100.0, 'FM999990.00'), '.', ',') ||
          case when r.payment_method is not null then E'\nAfgerekend: ' || r.payment_method else '' end ||
          coalesce(E'\nOpmerking: ' || r.note, '')) || nl ||
      'END:VEVENT' || nl;
  end loop;
  for r in select * from blocks where ends_at > now() - interval '30 days' order by starts_at loop
    v := v || 'BEGIN:VEVENT' || nl || 'UID:blok-' || r.id || '@nailbarbyfran' || nl ||
      'DTSTAMP:' || to_char(r.created_at at time zone 'UTC', f) || nl ||
      'DTSTART:' || to_char(r.starts_at at time zone 'UTC', f) || nl ||
      'DTEND:' || to_char(r.ends_at at time zone 'UTC', f) || nl ||
      'SUMMARY:' || ics_escape('Agenda dicht' || coalesce(' · ' || r.reason, '')) || nl ||
      'TRANSP:OPAQUE' || nl || 'END:VEVENT' || nl;
  end loop;
  return v || 'END:VCALENDAR' || nl;
end $$;

revoke all on function public.calendar_feed(uuid) from public;
grant execute on function public.calendar_feed(uuid) to anon, authenticated;
