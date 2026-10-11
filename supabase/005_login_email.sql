-- Nail Bar by Fran — update 005: inloggen met nails.byfran@outlook.com (wachtwoord blijft hetzelfde)
update auth.users
   set email = 'nails.byfran@outlook.com', email_confirmed_at = coalesce(email_confirmed_at, now()), updated_at = now()
 where email = 'admin@nailsbyfrances.nl';
update auth.identities
   set identity_data = identity_data || jsonb_build_object('email', 'nails.byfran@outlook.com'), updated_at = now()
 where provider = 'email' and identity_data->>'email' = 'admin@nailsbyfrances.nl';
update public.admins set email = 'nails.byfran@outlook.com' where email = 'admin@nailsbyfrances.nl';
select u.email as login, (select count(*) from public.admins a where a.email = u.email) as is_beheerder
  from auth.users u where u.email = 'nails.byfran@outlook.com';
