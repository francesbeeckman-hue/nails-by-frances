-- Nail Bar by Fran — update 008: herinneringsmail 1 dag én 1 uur voor de afspraak
-- Plak dit in Supabase > SQL Editor > New query en klik Run.
-- Supabase roept elke 10 minuten de website aan, die de herinneringen verstuurt.

create extension if not exists pg_cron;
create extension if not exists pg_net;

alter table public.bookings add column if not exists reminder_1h_sent_at timestamptz;

-- Bestaande afspraken die al (bijna) begonnen zijn niet alsnog mailen
update public.bookings set reminder_1h_sent_at = now()
 where reminder_1h_sent_at is null and starts_at < now() + interval '65 minutes';

create or replace function public.run_reminders()
returns void
language plpgsql security definer set search_path = public as $$
declare s record;
begin
  select webhook_url, webhook_secret into s from private_settings limit 1;
  if s.webhook_url is null or s.webhook_url = '' then return; end if;
  perform net.http_post(
    url := replace(s.webhook_url, '/api/booking-mail', '/api/reminders'),
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', s.webhook_secret),
    timeout_milliseconds := 20000
  );
end $$;
revoke all on function public.run_reminders() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'herinneringen';
select cron.schedule('herinneringen', '*/10 * * * *', 'select public.run_reminders()');

select jobname, schedule, active from cron.job where jobname = 'herinneringen';
