-- A demo book for the screen pictures, the store listing and trying Monee:
-- a year in the life of someone working in Riyadh who sends money home to
-- Kerala. Main currency SAR, with INR and BHD accounts, wallets, a bank, a
-- credit card, a debit card, savings, gold and a car loan. Dates follow
-- today, so the book always looks current. Safe to run again (it starts over).
--
-- Signed in as demo@skifi.co (user dddddddd-0000-0000-0000-000000000001).

do $$
declare
  uid uuid := 'dddddddd-0000-0000-0000-000000000001';
  b uuid := 'dddddddd-0000-0000-0000-0000000000b1';
  today date; start date; d date; i int; m date;
  a_cash uuid; a_cash_inr uuid; a_cash_bhd uuid; a_stc uuid; a_barq uuid; a_rajhi uuid; a_federal uuid; a_card uuid; a_mada uuid;
  a_save uuid; a_gold uuid; a_loan uuid;
  c record;
  function_cat jsonb := '{}';
begin
  delete from public.books where id = b;
  insert into auth.users (id, email, email_confirmed_at) values (uid, 'demo@skifi.co', now()) on conflict (id) do nothing;
  insert into public.books (id, name, currency, timezone, created_by) values (b, 'My money', 'SAR', 'Asia/Riyadh', uid);
  insert into public.book_members (book_id, user_id, name, email, role) values (b, uid, 'Riyas', 'demo@skifi.co', 'owner');
  perform public.seed_book(b);
  today := public.book_today(b);
  start := (date_trunc('month', today) - interval '11 months')::date;
  perform setseed(0.42);

  insert into public.currency_rates (book_id, currency, rate) values (b, 'INR', 0.0440), (b, 'BHD', 9.9500);

  -- Accounts, in the seeded groups. The seeded Cash and Bank account are renamed.
  update public.accounts set name = 'Cash SAR' where book_id = b and name = 'Cash' returning id into a_cash;
  update public.accounts set name = 'Al Rajhi' where book_id = b and name = 'Bank account' returning id into a_rajhi;
  update public.accounts set opening_balance = 1500 where id = a_cash;
  update public.accounts set opening_balance = 8200 where id = a_rajhi;
  insert into public.accounts (book_id, group_id, name, currency, opening_balance, sort)
    select b, x.id, 'Cash INR', 'INR', 4000, 20 from public.account_groups x where x.book_id = b and x.kind = 'cash' returning id into a_cash_inr;
  insert into public.accounts (book_id, group_id, name, currency, opening_balance, sort)
    select b, x.id, 'Cash BD', 'BHD', 12.5, 30 from public.account_groups x where x.book_id = b and x.kind = 'cash' returning id into a_cash_bhd;
  insert into public.accounts (book_id, group_id, name, opening_balance, sort)
    select b, x.id, 'STC Pay', 120, 10 from public.account_groups x where x.book_id = b and x.kind = 'prepaid' returning id into a_stc;
  insert into public.accounts (book_id, group_id, name, opening_balance, sort)
    select b, x.id, 'Barq', 40, 20 from public.account_groups x where x.book_id = b and x.kind = 'prepaid' returning id into a_barq;
  insert into public.accounts (book_id, group_id, name, currency, opening_balance, sort)
    select b, x.id, 'Federal Bank', 'INR', 25000, 20 from public.account_groups x where x.book_id = b and x.kind = 'bank' returning id into a_federal;
  insert into public.accounts (book_id, group_id, name, settlement_day, payment_day, billing_account_id, auto_pay, autopaid_until, opening_balance)
    select b, x.id, 'SAB Credit', 1, 25, a_rajhi, true, start, -650 from public.account_groups x where x.book_id = b and x.kind = 'card' returning id into a_card;
  insert into public.accounts (book_id, group_id, name, linked_account_id)
    select b, x.id, 'Mada', a_rajhi from public.account_groups x where x.book_id = b and x.kind = 'debit_card' returning id into a_mada;
  insert into public.accounts (book_id, group_id, name, transfer_expense, opening_balance)
    select b, x.id, 'Emergency fund', true, 3000 from public.account_groups x where x.book_id = b and x.kind = 'savings' returning id into a_save;
  insert into public.accounts (book_id, group_id, name, opening_balance)
    select b, x.id, 'Gold', 6400 from public.account_groups x where x.book_id = b and x.kind = 'investment' returning id into a_gold;
  insert into public.accounts (book_id, group_id, name, opening_balance)
    select b, x.id, 'Car loan', -38000 from public.account_groups x where x.book_id = b and x.kind = 'loan' returning id into a_loan;

  -- Category ids by name ("Food" or "Food/Groceries").
  for c in select x.id, coalesce(p.name || '/', '') || x.name as k from public.categories x
             left join public.categories p on p.id = x.parent_id where x.book_id = b loop
    function_cat := function_cat || jsonb_build_object(c.k, c.id);
  end loop;

  -- Every month: salary, rent, bills, money home, savings, the car loan.
  m := start;
  while m <= today loop
    insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
    select b, 'income', public.month_day(m, 27) + time '09:00', a_rajhi, (function_cat ->> 'Salary')::uuid, 12500, 'Salary'
     where public.month_day(m, 27) <= today;
    insert into public.txns (book_id, kind, at, account_id, category_id, amount, note) values
      (b, 'expense', m + time '10:00', a_rajhi, (function_cat ->> 'Home/Rent')::uuid, 2000, 'Flat rent');
    insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
    select b, 'expense', public.month_day(m, 5) + time '18:00', a_stc, (function_cat ->> 'Bills/Phone')::uuid, 99, 'STC postpaid'
     where public.month_day(m, 5) <= today;
    insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
    select b, 'expense', public.month_day(m, 8) + time '18:00', a_rajhi, (function_cat ->> 'Bills/Electricity')::uuid, round((140 + random() * 160)::numeric, 2), 'SEC bill'
     where public.month_day(m, 8) <= today;
    insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, to_amount, note)
    select b, 'transfer', public.month_day(m, 28) + time '20:00', a_rajhi, a_federal, 3000, round(3000 / 0.0440, 2), 'Home'
     where public.month_day(m, 28) <= today;
    insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, note)
    select b, 'transfer', public.month_day(m, 28) + time '20:30', a_rajhi, a_save, 500, 'Emergency fund'
     where public.month_day(m, 28) <= today;
    insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, note)
    select b, 'transfer', public.month_day(m, 15) + time '09:00', a_rajhi, a_loan, 1450, 'Car loan EMI'
     where public.month_day(m, 15) <= today;
    insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
    select b, 'expense', public.month_day(m, 12) + time '19:00', a_federal, (function_cat ->> 'Family/Support')::uuid, round((48000 + random() * 14000)::numeric, 0), 'Umma'
     where public.month_day(m, 12) <= today;
    -- Topping up cash and the wallets from the bank.
    insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, note)
    select b, 'transfer', public.month_day(m, 2) + time '12:00', a_rajhi, v.acc, v.amt, 'Top up'
      from (values (a_cash, 330), (a_stc, 150), (a_barq, 170)) v(acc, amt)
     where public.month_day(m, 2) <= today;
    m := (m + interval '1 month')::date;
  end loop;
  insert into public.txns (book_id, kind, at, account_id, to_account_id, amount, note)
  values (b, 'transfer', (today - 122) + time '09:00', a_federal, a_cash_inr, 12000, 'ATM');

  -- Day to day: groceries, fuel, eating out, taxis, shopping on the card.
  d := start;
  while d <= today loop
    if extract(dow from d) in (4, 5) then
      insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
      values (b, 'expense', d + time '19:30', case when random() < 0.5 then a_mada else a_card end,
              (function_cat ->> 'Food/Groceries')::uuid, round((80 + random() * 260)::numeric, 2),
              (array['Lulu', 'Danube', 'Panda', 'Tamimi'])[1 + floor(random() * 4)::int]);
    end if;
    if random() < 0.28 then
      insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
      values (b, 'expense', d + time '13:15', case when random() < 0.6 then a_cash else a_barq end,
              (function_cat ->> 'Food/Eating out')::uuid, round((18 + random() * 70)::numeric, 2),
              (array['Al Baik', 'Kerala hotel', 'Shawarma', 'Tea and snacks', 'Biryani'])[1 + floor(random() * 5)::int]);
    end if;
    if extract(dow from d) = 6 or random() < 0.08 then
      insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
      values (b, 'expense', d + time '08:10', a_mada, (function_cat ->> 'Transport/Fuel')::uuid, round((60 + random() * 50)::numeric, 2), 'Petrol');
    end if;
    if random() < 0.06 then
      insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
      values (b, 'expense', d + time '21:00', a_card, (function_cat ->> 'Shopping')::uuid, round((90 + random() * 600)::numeric, 2),
              (array['Noon', 'Amazon', 'Centrepoint', 'Extra'])[1 + floor(random() * 4)::int]);
    end if;
    if random() < 0.05 then
      insert into public.txns (book_id, kind, at, account_id, category_id, amount, note)
      values (b, 'expense', d + time '22:40', a_stc, (function_cat ->> 'Transport/Taxi')::uuid, round((15 + random() * 45)::numeric, 2), 'Careem');
    end if;
    d := d + 1;
  end loop;

  -- A trip home in INR, a weekend in Bahrain, and a health visit.
  insert into public.txns (book_id, kind, at, account_id, category_id, amount, note) values
    (b, 'expense', (today - 120) + time '11:00', a_cash_inr, (function_cat ->> 'Travel')::uuid, 3800, 'Kochi taxi and hotel'),
    (b, 'expense', (today - 118) + time '17:00', a_cash_inr, (function_cat ->> 'Gifts')::uuid, 5200, 'Gifts for family'),
    (b, 'expense', (today - 40) + time '20:00', a_cash_bhd, (function_cat ->> 'Food/Eating out')::uuid, 7.8, 'Manama dinner'),
    (b, 'expense', (today - 9) + time '10:30', a_card, (function_cat ->> 'Health/Doctor')::uuid, 220, 'Clinic');

  -- What happens by itself, and what to aim for.
  insert into public.repeat_rules (book_id, kind, account_id, category_id, amount, note, freq, starts_on, done)
  values (b, 'income', a_rajhi, (function_cat ->> 'Salary')::uuid, 12500, 'Salary', 'month', public.month_day(start, 27), 0),
         (b, 'expense', a_rajhi, (function_cat ->> 'Home/Rent')::uuid, 2000, 'Flat rent', 'month', start, 0);
  update public.repeat_rules r set done = (select count(*) from public.repeat_dates(r, r.starts_on, today)) where r.book_id = b;
  update public.txns t set repeat_id = (select r.id from public.repeat_rules r where r.book_id = b and r.note = t.note)
   where t.book_id = b and t.note in ('Salary', 'Flat rent');
  insert into public.budgets (book_id, category_id, amount, from_month)
  select b, x.id, v.amount, start from public.categories x
    join (values ('Food', 1500), ('Transport', 600), ('Shopping', 800), ('Bills', 450), ('Family', 3000)) v(name, amount)
      on v.name = x.name
   where x.book_id = b and x.kind = 'expense' and x.parent_id is null;
  insert into public.tags (book_id, name) values (b, 'trip'), (b, 'family');
  insert into public.txn_tags (book_id, txn_id, tag_id)
  select b, t.id, (select tg.id from public.tags tg where tg.book_id = b and tg.name = 'trip')
    from public.txns t where t.book_id = b and t.note in ('Kochi taxi and hotel', 'Gifts for family', 'Manama dinner');
  insert into public.day_memos (book_id, day, text, color) values (b, today - 3, 'Ask landlord about the AC', '#6D4AE8');

  -- The card is paid on its payment day, as catch_up would have done.
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'email', 'demo@skifi.co')::text, true);
  perform set_config('request.headers', json_build_object('x-book-id', b)::text, true);
  perform public.catch_up();
  perform set_config('request.jwt.claims', '', true);
  perform set_config('request.headers', '', true);
end $$;
