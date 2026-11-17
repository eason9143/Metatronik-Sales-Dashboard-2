-- Metatronik Sales Dashboard - SAMPLE data only (file 3 of 4)
-- Run AFTER 02_rules_and_upload.sql. Paste into Supabase > SQL Editor and click Run.
-- Safe to run more than once: days that already have sample data are skipped.
-- Creates made-up orders for the 13 days before yesterday.
-- Yesterday is left empty on purpose, so you can test the "not uploaded yet" warning
-- and then upload sample-upload.csv.

do $$
declare
  d date;
  n int;
  i int;
  v_upload_id bigint;
  customers text[] := array['Tan Ah Kow','Siti Aminah','Raj Kumar','Lim Mei Ling','Ahmad Faizal',
                            'Wong Kar Wai','Nurul Huda','Chong Wei','Priya Devi','Hafiz Rahman',
                            'Lee Siew Lan','Muthu Samy','Aisyah Zainal','Ong Boon Hock','Farah Nadia'];
begin
  perform setseed(0.42);
  for d in select generate_series(current_date - 14, current_date - 2, interval '1 day')::date loop
    if exists (select 1 from public.uploads u where u.file_name = 'sample-' || to_char(d, 'YYYY-MM-DD') || '.xlsx') then
      continue;
    end if;

    n := 6 + floor(random() * 9)::int;  -- 6 to 14 orders that day
    for i in 1..n loop
      insert into public.orders (order_id, order_date, customer_name, amount_rm, status)
      values ('SMP-' || to_char(d, 'YYMMDD') || '-' || lpad(i::text, 2, '0'),
              d,
              customers[1 + floor(random() * array_length(customers, 1))::int],
              round((50 + random() * 750)::numeric, 2),
              case when random() < 0.15 then 'Cancelled' else 'Confirmed' end)
      on conflict (order_id) do nothing;
    end loop;

    insert into public.uploads (file_name, order_date, order_count, confirmed_count, cancelled_count, total_rm)
    select 'sample-' || to_char(d, 'YYYY-MM-DD') || '.xlsx', d,
           count(*),
           count(*) filter (where status = 'Confirmed'),
           count(*) filter (where status = 'Cancelled'),
           coalesce(sum(amount_rm) filter (where status = 'Confirmed'), 0)
    from public.orders where order_date = d and order_id like 'SMP-%'
    returning id into v_upload_id;

    update public.orders set upload_id = v_upload_id
     where order_date = d and order_id like 'SMP-%' and upload_id is null;
  end loop;
end $$;
