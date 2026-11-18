-- Nail Studio by Frances — update 010: afspraak verzetten stuurt de klant een mail met de nieuwe tijd
-- Plak dit in Supabase > SQL Editor > New query en klik Run.

drop trigger if exists bookings_notify_move on public.bookings;
create trigger bookings_notify_move after update of starts_at on public.bookings
  for each row when (old.starts_at is distinct from new.starts_at and new.status = 'confirmed')
  execute function public.notify_booking();
