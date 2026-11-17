-- Metatronik Sales Dashboard - database setup (file 1 of 3)
-- Paste into Supabase > SQL Editor and click Run. Safe to run more than once.

-- ============ PEOPLE AND ROLES ============
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  role text not null default 'staff' check (role in ('owner','manager','staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

-- Returns the signed-in person's role, only if they are switched on.
create or replace function public.my_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p
  where p.id = auth.uid() and p.active = true
$$;

-- Create a profile automatically when someone signs up.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ SETTINGS ============
create table if not exists public.settings (
  key text primary key,
  value text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);
alter table public.settings enable row level security;

insert into public.settings (key, value) values
  ('upload_deadline', '08:00'),
  ('owner_whatsapp', ''),
  ('chart_days', '14')
on conflict (key) do nothing;

-- ============ HISTORY (AUDIT LOG) ============
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  who_email text,
  action text not null,
  table_name text,
  record_id text,
  details jsonb
);
alter table public.audit_log enable row level security;

create or replace function public.write_audit(p_action text, p_table text, p_record text, p_details jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (created_by, who_email, action, table_name, record_id, details)
  values (auth.uid(),
          coalesce((select p.email from public.profiles p where p.id = auth.uid()), 'System'),
          p_action, p_table, p_record, p_details);
end;
$$;
revoke execute on function public.write_audit(text, text, text, jsonb) from public, anon, authenticated;

-- ============ BUSINESS TABLE 1: UPLOADS ============
create table if not exists public.uploads (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  file_name text not null,
  order_date date not null,
  order_count int not null default 0,
  confirmed_count int not null default 0,
  cancelled_count int not null default 0,
  total_rm numeric(12,2) not null default 0
);
alter table public.uploads enable row level security;

-- ============ BUSINESS TABLE 2: ORDERS ============
create table if not exists public.orders (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  order_id text not null unique,
  order_date date not null,
  customer_name text not null default '',
  amount_rm numeric(12,2) not null check (amount_rm >= 0),
  status text not null check (status in ('Confirmed','Cancelled')),
  upload_id bigint references public.uploads(id) on delete set null
);
alter table public.orders enable row level security;
create index if not exists orders_order_date_idx on public.orders (order_date);

-- ============ AI BRIEFS ============
create table if not exists public.ai_briefs (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  for_date date not null,
  prompt text not null,
  answer text not null,
  checked boolean not null default false check (checked = true)
);
alter table public.ai_briefs enable row level security;

-- ============ DAILY TOTALS (follows the same security as orders) ============
create or replace view public.daily_sales with (security_invoker = true) as
select order_date,
       count(*)::int as order_count,
       count(*) filter (where status = 'Confirmed')::int as confirmed_count,
       count(*) filter (where status = 'Cancelled')::int as cancelled_count,
       coalesce(sum(amount_rm) filter (where status = 'Confirmed'), 0)::numeric(12,2) as total_rm
from public.orders
group by order_date;

-- ============ ACCESS RULES (ROW LEVEL SECURITY) ============
-- profiles: you see yourself; the owner sees and edits everyone.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.my_role() = 'owner');
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

-- settings: everyone signed in reads; only the owner changes.
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings for select to authenticated
  using (public.my_role() in ('owner','manager','staff'));
drop policy if exists settings_insert on public.settings;
create policy settings_insert on public.settings for insert to authenticated
  with check (public.my_role() = 'owner');
drop policy if exists settings_update on public.settings;
create policy settings_update on public.settings for update to authenticated
  using (public.my_role() = 'owner') with check (public.my_role() = 'owner');

-- audit_log: manager and owner read. Nobody writes directly.
drop policy if exists audit_select on public.audit_log;
create policy audit_select on public.audit_log for select to authenticated
  using (public.my_role() in ('owner','manager'));

-- uploads: everyone reads; uploads are made through import_orders(); owner deletes.
drop policy if exists uploads_select on public.uploads;
create policy uploads_select on public.uploads for select to authenticated
  using (public.my_role() in ('owner','manager','staff'));
drop policy if exists uploads_delete on public.uploads;
create policy uploads_delete on public.uploads for delete to authenticated
  using (public.my_role() = 'owner');

-- orders: everyone reads (approved in SPEC); only the owner edits or deletes by hand.
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select to authenticated
  using (public.my_role() in ('owner','manager','staff'));
drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert to authenticated
  with check (public.my_role() = 'owner');
drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders for update to authenticated
  using (public.my_role() = 'owner') with check (public.my_role() = 'owner');
drop policy if exists orders_delete on public.orders;
create policy orders_delete on public.orders for delete to authenticated
  using (public.my_role() = 'owner');

-- ai_briefs: owner and manager read and save (must be ticked as checked); owner deletes.
drop policy if exists briefs_select on public.ai_briefs;
create policy briefs_select on public.ai_briefs for select to authenticated
  using (public.my_role() in ('owner','manager'));
drop policy if exists briefs_insert on public.ai_briefs;
create policy briefs_insert on public.ai_briefs for insert to authenticated
  with check (public.my_role() in ('owner','manager') and checked = true);
drop policy if exists briefs_delete on public.ai_briefs;
create policy briefs_delete on public.ai_briefs for delete to authenticated
  using (public.my_role() = 'owner');
