-- Metatronik Sales Dashboard - rules, history and file upload (file 2 of 3)
-- Run AFTER schema.sql. Paste into Supabase > SQL Editor and click Run. Safe to run more than once.

-- ============ ONLY THE OWNER CAN CHANGE ROLES OR SWITCH PEOPLE ON/OFF ============
create or replace function public.protect_profile_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (new.role is distinct from old.role or new.active is distinct from old.active) then
    -- auth.uid() is null when run from the Supabase SQL Editor: allowed.
    if auth.uid() is not null and coalesce(public.my_role(), '') <> 'owner' then
      raise exception 'Only the owner can change roles or switch people on or off.';
    end if;
    -- Never leave the system without an active owner.
    if old.role = 'owner' and old.active = true and (new.role <> 'owner' or new.active = false)
       and not exists (select 1 from public.profiles p
                       where p.role = 'owner' and p.active = true and p.id <> old.id) then
      raise exception 'There must always be at least one active owner.';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_profile_fields on public.profiles;
create trigger protect_profile_fields
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- ============ HISTORY: PEOPLE ============
create or replace function public.audit_profiles()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit('sign_up', 'profiles', new.email, jsonb_build_object('role', new.role));
  elsif new.role is distinct from old.role or new.active is distinct from old.active then
    perform public.write_audit('role_change', 'profiles', new.email,
      jsonb_build_object('old_role', old.role, 'new_role', new.role,
                         'old_active', old.active, 'new_active', new.active));
  end if;
  return new;
end;
$$;
drop trigger if exists audit_profiles on public.profiles;
create trigger audit_profiles
  after insert or update on public.profiles
  for each row execute function public.audit_profiles();

-- ============ HISTORY: ORDERS ============
create or replace function public.audit_orders()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    perform public.write_audit('create', 'orders', new.order_id,
      jsonb_build_object('status', new.status, 'amount_rm', new.amount_rm, 'order_date', new.order_date));
    return new;
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status then
      perform public.write_audit('status_change', 'orders', new.order_id,
        jsonb_build_object('old_status', old.status, 'new_status', new.status));
    end if;
    if new.amount_rm is distinct from old.amount_rm or new.customer_name is distinct from old.customer_name
       or new.order_date is distinct from old.order_date then
      perform public.write_audit('edit', 'orders', new.order_id,
        jsonb_build_object('old_amount_rm', old.amount_rm, 'new_amount_rm', new.amount_rm,
                           'old_customer', old.customer_name, 'new_customer', new.customer_name,
                           'old_date', old.order_date, 'new_date', new.order_date));
    end if;
    return new;
  else
    perform public.write_audit('delete', 'orders', old.order_id,
      jsonb_build_object('status', old.status, 'amount_rm', old.amount_rm));
    return old;
  end if;
end;
$$;
drop trigger if exists audit_orders on public.orders;
create trigger audit_orders
  after insert or update or delete on public.orders
  for each row execute function public.audit_orders();

-- ============ HISTORY: UPLOADS ============
create or replace function public.audit_uploads()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.write_audit('upload', 'uploads', new.file_name,
    jsonb_build_object('order_date', new.order_date, 'orders', new.order_count,
                       'confirmed', new.confirmed_count, 'cancelled', new.cancelled_count,
                       'total_rm', new.total_rm));
  return new;
end;
$$;
drop trigger if exists audit_uploads on public.uploads;
create trigger audit_uploads
  after insert on public.uploads
  for each row execute function public.audit_uploads();

-- ============ HISTORY: SETTINGS ============
create or replace function public.audit_settings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.value is distinct from old.value then
    perform public.write_audit('setting_change', 'settings', new.key,
      jsonb_build_object('old_value', old.value, 'new_value', new.value));
  end if;
  return new;
end;
$$;
drop trigger if exists audit_settings on public.settings;
create trigger audit_settings
  after update on public.settings
  for each row execute function public.audit_settings();

-- ============ FILE UPLOAD (owner and manager) ============
-- Saves a whole file at once: if any row is wrong, nothing is saved.
-- The same Order ID uploaded again updates the existing order (no duplicates).
create or replace function public.import_orders(p_file_name text, p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.my_role();
  r jsonb;
  v_row int;
  v_upload_id bigint;
  v_new int := 0;
  v_changed int := 0;
  v_same int := 0;
  v_exists public.orders%rowtype;
  v_date date;
  v_amount numeric(12,2);
  v_status text;
  v_id text;
begin
  if v_role is null or v_role not in ('owner','manager') then
    raise exception 'Only the owner or a manager can upload files.';
  end if;
  if p_rows is null or jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 then
    raise exception 'The file has no orders in it.';
  end if;

  -- Check every row first.
  for r in select * from jsonb_array_elements(p_rows) loop
    v_row := coalesce((r->>'row')::int, 0);
    v_id := btrim(coalesce(r->>'order_id', ''));
    if v_id = '' then
      raise exception 'Row %: Order ID is empty.', v_row;
    end if;
    begin
      v_date := (r->>'order_date')::date;
    exception when others then
      raise exception 'Row %: Order Date is not a valid date.', v_row;
    end;
    if v_date is null then
      raise exception 'Row %: Order Date is empty.', v_row;
    end if;
    begin
      v_amount := (r->>'amount_rm')::numeric(12,2);
    exception when others then
      raise exception 'Row %: Amount is not a number.', v_row;
    end;
    if v_amount is null or v_amount < 0 then
      raise exception 'Row %: Amount must be zero or more.', v_row;
    end if;
    if coalesce(r->>'status', '') not in ('Confirmed','Cancelled') then
      raise exception 'Row %: Status must be Confirmed or Cancelled.', v_row;
    end if;
  end loop;

  if (select count(distinct btrim(e->>'order_id')) from jsonb_array_elements(p_rows) e)
     <> jsonb_array_length(p_rows) then
    raise exception 'The same Order ID appears more than once in this file.';
  end if;

  -- Record the upload.
  insert into public.uploads (file_name, order_date, order_count, confirmed_count, cancelled_count, total_rm)
  select coalesce(nullif(btrim(p_file_name), ''), 'upload'),
         max((e->>'order_date')::date),
         count(*),
         count(*) filter (where e->>'status' = 'Confirmed'),
         count(*) filter (where e->>'status' = 'Cancelled'),
         coalesce(sum((e->>'amount_rm')::numeric(12,2)) filter (where e->>'status' = 'Confirmed'), 0)
  from jsonb_array_elements(p_rows) e
  returning id into v_upload_id;

  -- Save each order.
  for r in select * from jsonb_array_elements(p_rows) loop
    v_id := btrim(r->>'order_id');
    v_date := (r->>'order_date')::date;
    v_amount := (r->>'amount_rm')::numeric(12,2);
    v_status := r->>'status';
    select * into v_exists from public.orders o where o.order_id = v_id;
    if not found then
      insert into public.orders (order_id, order_date, customer_name, amount_rm, status, upload_id)
      values (v_id, v_date, btrim(coalesce(r->>'customer_name', '')), v_amount, v_status, v_upload_id);
      v_new := v_new + 1;
    elsif v_exists.status is distinct from v_status
       or v_exists.amount_rm is distinct from v_amount
       or v_exists.order_date is distinct from v_date
       or v_exists.customer_name is distinct from btrim(coalesce(r->>'customer_name', '')) then
      update public.orders
         set order_date = v_date,
             customer_name = btrim(coalesce(r->>'customer_name', '')),
             amount_rm = v_amount,
             status = v_status,
             upload_id = v_upload_id
       where order_id = v_id;
      v_changed := v_changed + 1;
    else
      v_same := v_same + 1;
    end if;
  end loop;

  return jsonb_build_object('upload_id', v_upload_id, 'new', v_new, 'changed', v_changed, 'unchanged', v_same);
end;
$$;
revoke execute on function public.import_orders(text, jsonb) from public, anon;
grant execute on function public.import_orders(text, jsonb) to authenticated;
