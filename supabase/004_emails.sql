-- Nail Bar by Fran — update 004: e-mails (bevestiging, annulering, herinnering)
-- Plak dit in Supabase > SQL Editor > New query en klik Run.
-- Onderaan verschijnt je WEBHOOK_SECRET: kopieer die naar Vercel (zie instructies).

create extension if not exists pg_net;

alter table public.bookings add column if not exists reminder_sent_at timestamptz;
alter table public.private_settings add column if not exists webhook_secret text not null default encode(extensions.gen_random_bytes(24), 'hex');
alter table public.private_settings add column if not exists webhook_url text not null default 'https://nails-by-frances-website.vercel.app/api/booking-mail';

create or replace function public.notify_booking()
returns trigger
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select webhook_url, webhook_secret into s from private_settings limit 1;
  if s.webhook_url is null or s.webhook_url = '' then return new; end if;
  perform net.http_post(
    url := s.webhook_url,
    body := jsonb_build_object('type', TG_OP, 'record', to_jsonb(new), 'old_record', case when TG_OP = 'UPDATE' then to_jsonb(old) end),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', s.webhook_secret),
    timeout_milliseconds := 8000
  );
  return new;
exception when others then
  return new; -- een mailprobleem mag een boeking nooit tegenhouden
end $$;

drop trigger if exists bookings_notify_insert on public.bookings;
create trigger bookings_notify_insert after insert on public.bookings
  for each row execute function public.notify_booking();

drop trigger if exists bookings_notify_cancel on public.bookings;
create trigger bookings_notify_cancel after update of status on public.bookings
  for each row when (old.status is distinct from new.status and new.status = 'cancelled')
  execute function public.notify_booking();

select webhook_secret as "WEBHOOK_SECRET — kopieer dit naar Vercel" from public.private_settings;
