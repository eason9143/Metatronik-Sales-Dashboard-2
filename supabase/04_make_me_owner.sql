-- Metatronik Sales Dashboard - make yourself the Owner (file 4 of 4)
-- Do this AFTER you have signed up in the app.
-- 1. Replace YOUR-EMAIL-HERE below with the email you signed up with (keep the quotes).
-- 2. Paste into Supabase > SQL Editor and click Run. Safe to run more than once.

update public.profiles
   set role = 'owner', active = true
 where lower(email) = lower('YOUR-EMAIL-HERE');

-- This should show one line with role = owner. If it shows nothing, check the email.
select email, role, active from public.profiles where role = 'owner';
