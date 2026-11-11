-- Monee's database rules, end to end, as the people who use it.
-- Run on a scratch database after platform.sql and every migration. Everything
-- happens in one transaction that is rolled back at the end.
begin;

create or replace function pg_temp.as_user(sub text, phone text, email text, book uuid default null) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', sub, 'role', 'authenticated', 'phone', phone, 'email', email)::text, true);
  perform set_config('request.headers', json_build_object('x-book-id', book)::text, true);
  execute 'set local role authenticated';
end $$;
create or replace function pg_temp.ok(cond boolean, what text) returns void language plpgsql as $$
begin
  if not coalesce(cond, false) then raise exception 'FAILED: %', what; end if;
  raise notice 'ok: %', what;
end $$;
create or replace function pg_temp.fails(stmt text, msg text, what text) returns void language plpgsql as $$
begin
  begin
    execute stmt;
  exception when others then
    if position(lower(msg) in lower(sqlerrm)) > 0 then raise notice 'ok: %', what; return; end if;
    raise exception 'FAILED: % (wrong error: %)', what, sqlerrm;
  end;
  raise exception 'FAILED: % (no error)', what;
end $$;
create or replace function pg_temp.rows(stmt text) returns int language plpgsql as $$
declare n int;
begin
  execute stmt;
  get diagnostics n = row_count;
  return n;
end $$;
create temp table t (k text primary key, v text);
grant all on t to authenticated, anon;
create or replace function pg_temp.put(key text, val text) returns void language sql as $$
  insert into t values (key, val) on conflict (k) do update set v = excluded.v;
$$;
create or replace function pg_temp.get(key text) returns text language sql as $$ select v from t where k = key; $$;
create or replace function pg_temp.id(key text) returns uuid language sql as $$ select v::uuid from t where k = key; $$;
-- An account's id by name, in the book being worked in.
create or replace function pg_temp.acc(n text) returns uuid language sql as $$ select id from public.accounts where name = n; $$;
create or replace function pg_temp.cat(n text, k text default 'expense') returns uuid language sql as $$
  select id from public.categories where name = n and kind = k order by parent_id nulls first limit 1;
$$;
create or replace function pg_temp.today() returns date language sql as $$ select public.book_today(public.current_book_id()); $$;
create or replace function pg_temp.bal(n text) returns numeric language sql as $$ select public.balance_at(pg_temp.acc(n), pg_temp.today()); $$;
create or replace function pg_temp.spend(acc text, amount numeric, cat text default 'Food', at timestamp default null) returns uuid language sql as $$
  select (public.save_txn(jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc(acc), 'category_id', pg_temp.cat(cat),
    'amount', amount, 'at', coalesce(at, pg_temp.today() + time '12:00'))) ->> 'id')::uuid;
$$;
grant execute on all functions in schema pg_temp to authenticated, anon;

-- People
--   Asha  owner of "Asha's money" (SAR), email          a1111111-...
--   Babu  owner of his own book                          b2222222-...
--   Dev   Asha's brother, may only look at her book      d3333333-...

-- ---------------------------------------------------------------- books
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com');
select pg_temp.ok((public.whoami() -> 'books') = '[]'::jsonb, 'a new sign-in has no book yet');
select pg_temp.put('b1', (public.create_book('Asha''s money', 'sar', 'Asia/Riyadh', 'Asha')) ->> 'book_id');
select pg_temp.ok(public.whoami() -> 'books' -> 0 ->> 'role' = 'owner', 'Asha started a book and owns it');
select pg_temp.ok(public.whoami() -> 'books' -> 0 ->> 'currency' = 'SAR', 'its main currency is SAR');
select pg_temp.ok((select count(*) from public.account_groups) = 10, 'it starts with ten account groups');
select pg_temp.ok((select count(*) from public.accounts) = 2, 'and a cash and a bank account');
select pg_temp.ok((select count(*) from public.categories where kind = 'expense' and parent_id is null) = 13, 'thirteen expense categories');
select pg_temp.ok((select count(*) from public.categories where parent_id is not null) > 10, 'with subcategories');
select pg_temp.fails($$update public.books set currency = 'INR'$$, 'from Currencies', 'the main currency changes only through set_main_currency');
reset role;

select pg_temp.as_user('b2222222-2222-2222-2222-222222222222', null, 'babu@example.com');
select pg_temp.put('b2', (public.create_book('Babu')) ->> 'book_id');
select pg_temp.ok((select count(*) from public.books) = 1, 'Babu sees only his own book');
select pg_temp.ok((select count(*) from public.accounts) = 2, 'and only his own accounts');
select pg_temp.fails(format($$insert into public.account_groups (book_id, name) values (%L, 'Sneaky')$$, pg_temp.get('b1')),
  'row-level security', 'Babu cannot add to Asha''s book');
select pg_temp.fails(format($$select public.save_txn(jsonb_build_object('kind', 'expense', 'account_id', %L, 'amount', 5))$$,
  (select id from public.accounts a where a.book_id = pg_temp.id('b1') limit 1)), 'another book', 'nor spend from her accounts');
reset role;
select pg_temp.ok((select count(*) from public.txns where book_id in (pg_temp.id('b1'), pg_temp.id('b2'))) = 0, 'nothing was written');

-- ---------------------------------------------------------------- income, expenses, transfers, currencies
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
insert into public.accounts (group_id, name, currency) select id, 'Cash INR', 'inr' from public.account_groups where kind = 'cash';
select pg_temp.ok((select currency from public.accounts where name = 'Cash INR') = 'INR', 'an account can keep another currency');
select pg_temp.fails($$select pg_temp.spend('Cash INR', 450)$$, 'exchange rate for INR', 'spending INR needs a rate first');
insert into public.currency_rates (currency, rate) values ('INR', 0.045);
select pg_temp.fails($$insert into public.currency_rates (currency, rate) values ('SAR', 2)$$, 'always 1', 'the main currency has no rate');

select public.save_txn(jsonb_build_object('kind', 'income', 'account_id', pg_temp.acc('Bank account'),
  'category_id', pg_temp.cat('Salary', 'income'), 'amount', 10000, 'at', pg_temp.today() + time '09:00', 'note', 'October salary'));
select pg_temp.spend('Cash', 50);
select pg_temp.spend('Cash INR', 450);
select pg_temp.ok(pg_temp.bal('Bank account') = 10000, 'salary lands in the bank');
select pg_temp.ok(pg_temp.bal('Cash') = -50, 'spending takes from cash');
select pg_temp.ok((select amount_main from public.entries where account_id = pg_temp.acc('Cash INR')) = 20.25, '450 INR counts as 20.25 SAR');
select pg_temp.fails($$select public.save_txn(jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Cash'), 'category_id', pg_temp.cat('Salary', 'income'), 'amount', 5))$$,
  'expense category', 'an expense needs an expense category');

select pg_temp.put('tr', public.save_txn(jsonb_build_object('kind', 'transfer', 'account_id', pg_temp.acc('Bank account'),
  'to_account_id', pg_temp.acc('Cash INR'), 'amount', 900, 'fee', 2, 'at', pg_temp.today() + time '10:00')) ->> 'to_amount');
select pg_temp.ok(pg_temp.get('tr')::numeric = 20000, 'a transfer into INR works out what arrived from the rates');
select pg_temp.ok(pg_temp.bal('Bank account') = 10000 - 902, 'the bank pays the amount and the fee');
select pg_temp.ok(pg_temp.bal('Cash INR') = 20000 - 450, 'the INR cash gets 20000');
select pg_temp.ok((select (public.period_totals(pg_temp.today(), pg_temp.today())) ->> 'expense')::numeric = 50 + 20.25 + 2,
  'a transfer is not an expense, but its fee is');
select pg_temp.ok((select (public.period_totals(pg_temp.today(), pg_temp.today())) ->> 'income')::numeric = 10000, 'income for the day');
select pg_temp.fails($$select public.save_txn(jsonb_build_object('kind', 'transfer', 'account_id', pg_temp.acc('Cash'), 'to_account_id', pg_temp.acc('Cash'), 'amount', 5))$$,
  'different account', 'a transfer goes somewhere else');

-- Splits and tags
select pg_temp.put('split', public.save_txn(jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Cash'), 'amount', 100,
  'at', pg_temp.today() + time '13:00', 'note', 'Lulu', 'tags', jsonb_build_array('trip', '#Trip', 'family'),
  'splits', jsonb_build_array(jsonb_build_object('category_id', pg_temp.cat('Food'), 'amount', 60),
                              jsonb_build_object('category_id', pg_temp.cat('Transport'), 'amount', 40)))) ->> 'id');
select pg_temp.ok((select count(*) from public.tags) = 2, 'tags are made by name, once each');
select pg_temp.ok((select (r ->> 'amount')::numeric from jsonb_array_elements(public.category_totals(pg_temp.today(), pg_temp.today()) -> 'rows') r
                    where r ->> 'name' = 'Transport') = 40, 'a split puts each part in its own category');
select pg_temp.ok(jsonb_array_length(public.txn_list(pg_temp.today(), pg_temp.today(), '{"tags":["trip"]}')) = 1, 'the list filters by tag');
select pg_temp.ok(jsonb_array_length(public.txn_list(pg_temp.today() - 400, pg_temp.today(), '{"q":"lulu"}')) = 1, 'search finds the note');
select pg_temp.ok(jsonb_array_length(public.txn_list(pg_temp.today() - 400, pg_temp.today(), '{"q":"transport"}')) = 1, 'and a split''s category');
select pg_temp.fails(format($$select public.save_txn(jsonb_build_object('id', %L, 'splits', jsonb_build_array(jsonb_build_object('category_id', pg_temp.cat('Food'), 'amount', 10)))); set constraints all immediate$$, pg_temp.get('split')),
  'add up to', 'split parts must add up to the whole');

-- ---------------------------------------------------------------- Transfer-Expense and debit cards
insert into public.accounts (group_id, name, transfer_expense) select id, 'Emergency fund', true from public.account_groups where kind = 'savings';
insert into public.accounts (group_id, name, transfer_expense) select id, 'Pocket', true from public.account_groups where kind = 'cash';
select pg_temp.ok(not (select transfer_expense from public.accounts where name = 'Pocket'), 'Transfer-Expense is only for savings, investment, loan and insurance');
select public.save_txn(jsonb_build_object('kind', 'transfer', 'account_id', pg_temp.acc('Bank account'), 'to_account_id', pg_temp.acc('Emergency fund'),
  'amount', 500, 'at', pg_temp.today() + time '11:00'));
select pg_temp.ok((select sum(amount_main) from public.entries where special = 'transfer' and kind = 'expense') = 500, 'money put into savings counts as an expense');
select pg_temp.ok(pg_temp.bal('Emergency fund') = 500, 'and the savings balance grows');

insert into public.accounts (group_id, name, linked_account_id) select id, 'Mada card', pg_temp.acc('Bank account') from public.account_groups where kind = 'debit_card';
select pg_temp.fails($$insert into public.accounts (group_id, name) select id, 'Loose card' from public.account_groups where kind = 'debit_card'$$,
  'Link the debit card', 'a debit card needs its account');
select pg_temp.put('bank_before', pg_temp.bal('Bank account')::text);
select pg_temp.spend('Mada card', 30, 'Food');
select pg_temp.ok(pg_temp.bal('Bank account') = pg_temp.get('bank_before')::numeric - 30, 'a debit card spends from its bank account');
select pg_temp.ok((select (a -> 'debit' ->> 'spent_this_month')::numeric from jsonb_array_elements(public.accounts_overview() -> 'groups') g,
                    jsonb_array_elements(g -> 'accounts') a where a ->> 'name' = 'Mada card') = 30, 'and shows what it spent this month');

-- ---------------------------------------------------------------- credit cards
insert into public.accounts (group_id, name, settlement_day, payment_day, billing_account_id)
  select id, 'Visa', 15, 10, pg_temp.acc('Bank account') from public.account_groups where kind = 'card';
select pg_temp.put('closed', public.last_settlement(15, pg_temp.today())::text);
select pg_temp.spend('Visa', 100, 'Shopping', (pg_temp.get('closed')::date - 3) + time '12:00');
select pg_temp.spend('Visa', 40, 'Shopping');
select pg_temp.ok((public.card_status(pg_temp.acc('Visa')) ->> 'payable')::numeric = 100, 'spending before the settlement day is payable');
select pg_temp.ok((public.card_status(pg_temp.acc('Visa')) ->> 'outstanding')::numeric = 40, 'spending since is outstanding');
select pg_temp.fails($$update public.accounts set billing_account_id = pg_temp.acc('Mada card') where name = 'Visa'$$,
  'cash or bank account', 'a card is paid from a cash or bank account');
select public.pay_card(pg_temp.acc('Visa'));
select pg_temp.ok((public.card_status(pg_temp.acc('Visa')) ->> 'payable')::numeric = 0, 'paying the card clears what was payable');
select pg_temp.ok((public.card_status(pg_temp.acc('Visa')) ->> 'outstanding')::numeric = 40, 'and leaves the open cycle');

select pg_temp.put('exp_at_time', (public.period_totals(pg_temp.today() - 40, pg_temp.today())) ->> 'expense');
update public.books set card_display = 'lump_sum';
select pg_temp.ok((public.period_totals(pg_temp.today() - 40, pg_temp.today()) ->> 'expense')::numeric
                  = pg_temp.get('exp_at_time')::numeric - 140 + 100, 'as a lump, card spending counts on the day the card is paid');
update public.books set card_display = 'at_time';

-- Automatic payment on payment day.
insert into public.accounts (group_id, name, settlement_day, payment_day, billing_account_id, opening_balance)
  select id, 'Amex', 1, 5, pg_temp.acc('Bank account'), -300 from public.account_groups where kind = 'card';
update public.accounts set auto_pay = true where name = 'Amex';
reset role;
update public.accounts set autopaid_until = public.month_day((public.book_today(pg_temp.id('b1')) - interval '1 month')::date, 5) - 1 where name = 'Amex';
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
select pg_temp.ok((public.catch_up() ->> 'card_payments')::int >= 1, 'catch_up pays a card automatically on payment day');
select pg_temp.ok((select sum(amount) from public.txns where to_account_id = pg_temp.acc('Amex')) = 300, 'paying what was owed');
select pg_temp.ok((public.catch_up() ->> 'card_payments')::int = 0, 'and never twice');

-- ---------------------------------------------------------------- repeats and instalments
select pg_temp.put('rep', public.add_repeat(jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Bank account'),
  'category_id', pg_temp.cat('Home'), 'amount', 1200, 'note', 'Rent', 'at', (pg_temp.today() - interval '2 months')::date + time '08:00'),
  'month') ->> 'recorded');
select pg_temp.ok(pg_temp.get('rep')::int = 3, 'a repeat from two months ago records three months up to today');
select pg_temp.ok((public.catch_up() ->> 'repeats')::int = 0, 'catching up again records nothing more');
select pg_temp.ok(jsonb_array_length(public.upcoming(pg_temp.today() + 1, pg_temp.today() + 62)) = 2, 'the next two show as upcoming');

select pg_temp.put('plan', public.add_instalments(jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Visa'),
  'category_id', pg_temp.cat('Shopping'), 'amount', 1000, 'note', 'Phone', 'at', pg_temp.today() + time '15:00'), 3) ->> 'plan_id');
select pg_temp.ok((select count(*) from public.txns where plan_id = pg_temp.id('plan')) = 3, 'an instalment plan records every month');
select pg_temp.ok((select array_agg(amount order by plan_no) from public.txns where plan_id = pg_temp.id('plan')) = array[333.34, 333.33, 333.33]::numeric[],
  'and the cents left over go on the first');
select pg_temp.ok((public.card_status(pg_temp.acc('Visa')) ->> 'outstanding')::numeric = 40 + 333.34, 'months still to come are not owed yet');
delete from public.instalment_plans where id = pg_temp.id('plan');
select pg_temp.ok((select count(*) from public.txns where note = 'Phone') = 0, 'deleting the plan deletes its months');

-- ---------------------------------------------------------------- budgets, carry-over, periods
insert into public.budgets (category_id, amount) values (pg_temp.cat('Food'), 750), (pg_temp.cat('Shopping'), 500);
select pg_temp.fails($$insert into public.budgets (category_id, amount) values (pg_temp.cat('Salary', 'income'), 5)$$, 'expense categories', 'budgets are for expenses');
select pg_temp.put('bs', public.budget_status(date_trunc('month', pg_temp.today())::date, (date_trunc('month', pg_temp.today()) + interval '1 month - 1 day')::date)::text);
select pg_temp.ok((pg_temp.get('bs')::jsonb -> 'total' ->> 'budget')::numeric = 1250, 'with no total budget, the total is the categories added up');
select pg_temp.ok((select (r ->> 'spent')::numeric from jsonb_array_elements(pg_temp.get('bs')::jsonb -> 'rows') r where r ->> 'name' = 'Food') = 50 + 20.25 + 60 + 30,
  'Food spent counts its splits and its subcategories');
insert into public.budgets (category_id, amount) values (null, 1800);
select pg_temp.ok((public.budget_status(pg_temp.today(), pg_temp.today()) -> 'total' ->> 'budget')::numeric = 1800, 'a total budget wins');

select pg_temp.ok((public.period_totals(pg_temp.today() + 1, pg_temp.today() + 1) ->> 'carry')::numeric = 0, 'no carry-over until it is switched on');
update public.books set carry_over = true;
select pg_temp.ok((public.period_totals(pg_temp.today() + 1, pg_temp.today() + 1) ->> 'carry')::numeric
                   = (select sum(case kind when 'income' then amount_main else -amount_main end) from public.entries where day <= pg_temp.today()),
  'carry-over brings everything before the period');
update public.books set month_start_day = 25;
select pg_temp.ok(public.month_range(pg_temp.id('b1'), 2026, 10) = daterange('2026-10-25', '2026-11-25', '[)'), 'a month starting on the 25th');
update public.books set month_start_day = 31;
select pg_temp.ok(public.month_range(pg_temp.id('b1'), 2026, 2) = daterange('2026-02-28', '2026-03-31', '[)'), 'the 31st means the month''s last day');
update public.books set month_start_day = 1, carry_over = false;
select pg_temp.ok(jsonb_array_length(public.span_totals('2026-10-01', '2026-10-31', 'week')) = 5, 'October 2026 has five weeks from Sunday');

-- ---------------------------------------------------------------- the Accounts tab
select pg_temp.put('ov', public.accounts_overview()::text);
select pg_temp.ok((pg_temp.get('ov')::jsonb ->> 'assets')::numeric > 0, 'assets add up');
select pg_temp.ok((pg_temp.get('ov')::jsonb ->> 'total')::numeric
                   = (pg_temp.get('ov')::jsonb ->> 'assets')::numeric - (pg_temp.get('ov')::jsonb ->> 'liabilities')::numeric, 'total is assets less liabilities');
select pg_temp.ok((select (a ->> 'balance_main')::numeric from jsonb_array_elements(pg_temp.get('ov')::jsonb -> 'groups') g,
                    jsonb_array_elements(g -> 'accounts') a where a ->> 'name' = 'Cash INR') = round((20000 - 450) * 0.045, 4), 'INR balances in SAR at today''s rate');
select pg_temp.ok(jsonb_array_length(public.account_trend(pg_temp.acc('Bank account'), 3)) = 3, 'an account month by month');
select pg_temp.ok(jsonb_array_length(public.asset_trend(6)) = 6, 'and all assets month by month');

-- ---------------------------------------------------------------- the main currency
select public.set_main_currency('INR', 22.5);
select pg_temp.ok((select currency from public.books) = 'INR', 'the main currency can change');
select pg_temp.ok((select rate from public.currency_rates where currency = 'SAR') = 22.5, 'the old main currency gets the rate');
select pg_temp.ok((select rate from public.txns where account_id = pg_temp.acc('Cash INR') and kind = 'expense') = 1, 'INR entries are now at 1');
select pg_temp.ok((select amount_main from public.entries where note = 'October salary') = 225000, 'and old totals keep their value');

-- ---------------------------------------------------------------- import
select pg_temp.ok((public.import_rows(jsonb_build_array(
  jsonb_build_object('date', '2026-01-05 10:00', 'kind', 'Exp.', 'account', 'Old wallet', 'category', 'Coffee', 'subcategory', 'Beans', 'amount', 80),
  jsonb_build_object('date', '2026-01-06 10:00', 'kind', 'Income', 'account', 'Bank account', 'category', 'Salary', 'amount', 500)
)) ->> 'imported')::int = 2, 'rows import by name');
select pg_temp.ok((select count(*) from public.accounts where name = 'Old wallet') = 1, 'a new account is made for an unknown name');
select pg_temp.ok((select count(*) from public.categories where name in ('Coffee', 'Beans')) = 2, 'and its category and subcategory');
select pg_temp.ok((public.import_rows(jsonb_build_array(
  jsonb_build_object('date', '2026-01-07 10:00', 'kind', 'expense', 'account', 'Dollar bank', 'currency', 'USD', 'rate', 83.5,
                     'category', 'Coffee', 'amount', 1000, 'tags', jsonb_build_array('From the sheet')),
  jsonb_build_object('date', '2026-01-08 10:00', 'kind', 'transfer', 'account', 'Bank account', 'to_account', 'Dollar cash',
                     'to_currency', 'USD', 'to_amount', 30, 'amount', 100)
)) ->> 'imported')::int = 2, 'rows in another currency import');
select pg_temp.ok((select currency from public.accounts where name = 'Dollar bank') = 'USD', 'a new account takes the currency of its rows');
select pg_temp.ok((select currency from public.accounts where name = 'Dollar cash') = 'USD', 'and so does the other side of a transfer');
select pg_temp.ok((select rate from public.txns t join public.accounts a on a.id = t.account_id where a.name = 'Dollar bank') = 83.5,
                  'the rate of that day is kept');
select pg_temp.ok((select to_amount from public.txns where to_account_id = pg_temp.acc('Dollar cash')) = 30, 'and what arrived');
select pg_temp.ok((select count(*) from public.txn_tags tt join public.tags g on g.id = tt.tag_id where g.name = 'From the sheet') = 1, 'tags come along');
update public.currency_rates set rate = 90 where currency = 'USD';
select pg_temp.ok(public.balance_main_at(pg_temp.acc('Dollar cash'), public.book_today(public.current_book_id())) = 2250,
                  'money in another currency keeps the value it had on its day');
select pg_temp.ok((select (x ->> 'balance_main')::numeric from jsonb_array_elements(public.accounts_overview() -> 'groups') g,
                          jsonb_array_elements(g -> 'accounts') x where x ->> 'name' = 'Dollar cash') = 2250,
                  'and so do the totals, whatever today''s rate');
-- ---------------------------------------------------------------- one entry paid from several accounts
select pg_temp.put('cash0', pg_temp.bal('Cash')::text);
select pg_temp.put('bank0', pg_temp.bal('Bank account')::text);
select pg_temp.put('pay', public.save_txn_group(jsonb_build_array(
  jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Cash'), 'category_id', pg_temp.cat('Food'), 'amount', 30,
                     'note', 'Paid two ways', 'at', pg_temp.today() + time '09:00'),
  jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Bank account'), 'category_id', pg_temp.cat('Food'), 'amount', 70,
                     'note', 'Paid two ways', 'at', pg_temp.today() + time '09:00'))) ->> 'group');
select pg_temp.ok(pg_temp.get('pay') is not null, 'an expense paid from two accounts is one group');
select pg_temp.ok((select count(*) from public.txns where pay_group = pg_temp.id('pay')) = 2, 'with a transaction for each account');
select pg_temp.ok(pg_temp.bal('Cash') = pg_temp.get('cash0')::numeric - 30, 'cash pays its part');
select pg_temp.ok(pg_temp.bal('Bank account') = pg_temp.get('bank0')::numeric - 70, 'and the bank its part');
select pg_temp.ok((select max((r ->> 'pay_parts')::int) from jsonb_array_elements(
    public.txn_list(pg_temp.today() - 1, pg_temp.today(), '{"q":"paid two ways"}')) r) = 2, 'the list says how many parts it has');
select public.save_txn_group(jsonb_build_array(jsonb_build_object(
  'id', (select id from public.txns where pay_group = pg_temp.id('pay') and account_id = pg_temp.acc('Cash')),
  'kind', 'expense', 'amount', 100)), pg_temp.id('pay'));
select pg_temp.ok((select count(*) from public.txns where note = 'Paid two ways') = 1, 'back to one account, the other part goes');
select pg_temp.ok((select pay_group from public.txns where note = 'Paid two ways') is null, 'and what is left is an ordinary entry');
select pg_temp.ok(pg_temp.bal('Bank account') = pg_temp.get('bank0')::numeric, 'the bank has its money back');
select pg_temp.fails($$select public.save_txn_group(jsonb_build_array(
  jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Cash'), 'amount', 5),
  jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Cash'), 'amount', 5)))$$,
  'different account', 'each part needs its own account');
select pg_temp.fails($$select public.save_txn_group(jsonb_build_array(
  jsonb_build_object('kind', 'transfer', 'account_id', pg_temp.acc('Cash'), 'to_account_id', pg_temp.acc('Bank account'), 'amount', 5),
  jsonb_build_object('kind', 'expense', 'account_id', pg_temp.acc('Bank account'), 'amount', 5)))$$,
  'Only income and expenses', 'transfers are not split between accounts');
delete from public.txns where note = 'Paid two ways';

reset role;

-- ---------------------------------------------------------------- receipt photos
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
insert into storage.objects (bucket_id, name) values ('monee-photos', pg_temp.get('b1') || '/x/receipt.jpg');
insert into public.txn_photos (txn_id, path) select id, pg_temp.get('b1') || '/x/receipt.jpg' from public.txns limit 1;
select pg_temp.fails(format($$insert into public.txn_photos (txn_id, path) select id, %L from public.txns limit 1$$, pg_temp.get('b2') || '/x/r.jpg'),
  'not in this book', 'a photo row points at its own book''s file');
select pg_temp.fails(format($$insert into storage.objects (bucket_id, name) values ('monee-photos', %L)$$, pg_temp.get('b2') || '/x/r.jpg'),
  'row-level security', 'and nobody puts files in another book');
reset role;
select pg_temp.as_user('b2222222-2222-2222-2222-222222222222', null, 'babu@example.com', pg_temp.id('b2'));
select pg_temp.ok((select count(*) from storage.objects) = 0, 'Babu cannot see Asha''s receipts');
reset role;

-- ---------------------------------------------------------------- a shared book
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
insert into public.book_members (name, email, role) values ('Dev', 'Dev@Example.com', 'viewer');
select pg_temp.fails($$insert into public.book_members (name, email, role) values ('X', 'x@example.com', 'owner')$$, 'one owner', 'a book has one owner');
reset role;
select pg_temp.as_user('d3333333-3333-3333-3333-333333333333', null, 'dev@example.com', pg_temp.id('b1'));
select pg_temp.ok(public.whoami() -> 'books' -> 0 ->> 'role' = 'viewer', 'Dev joins Asha''s book when he signs in with his email');
select pg_temp.ok((select count(*) from public.txns) > 5, 'he can look');
select pg_temp.fails($$select pg_temp.spend('Cash', 5)$$, 'only look', 'but not write');
select pg_temp.ok(pg_temp.rows('delete from public.txns') = 0, 'or delete');
select pg_temp.fails($$select public.delete_book('Asha''s money')$$, 'only the owner', 'or delete the book');
reset role;

-- ---------------------------------------------------------------- feature requests
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
select pg_temp.fails($$select public.request_feature('no')$$, 'short title', 'a request needs a title');
select public.request_feature('Split one bill between cash and card', 'Some shops take part cash, part card.', 'must', '1.0.0', 'android', 'en');
select pg_temp.ok(jsonb_array_length(public.my_feature_requests()) = 1, 'Asha sees her own request');
select pg_temp.ok(not public.feature_owner(), 'she is not on the Pursee team');
select pg_temp.fails($$select public.all_feature_requests()$$, 'Pursee team', 'so she cannot read everyone''s');
select pg_temp.fails($$select count(*) from public.feature_requests$$, 'permission', 'or the table itself');
reset role;
select pg_temp.as_user('e5555555-5555-5555-5555-555555555555', null, 'contact@skifi.co');
select pg_temp.ok(public.feature_owner(), 'contact@skifi.co is on the Pursee team');
select pg_temp.ok((public.all_feature_requests() -> 'counts' ->> 'new')::int >= 1, 'and reads every request');
select pg_temp.ok(public.set_feature_request_status((public.all_feature_requests() -> 'requests' -> 0 ->> 'id')::bigint, 'planned', 'Coming soon') ->> 'status' = 'planned',
  'and can plan one with a note');
reset role;
select pg_temp.as_user('a1111111-1111-1111-1111-111111111111', null, 'asha@example.com', pg_temp.id('b1'));
select pg_temp.ok(public.my_feature_requests() -> 0 ->> 'owner_note' = 'Coming soon', 'Asha reads the team''s note');
reset role;

-- ---------------------------------------------------------------- leaving
select pg_temp.as_user('b2222222-2222-2222-2222-222222222222', null, 'babu@example.com', pg_temp.id('b2'));
select pg_temp.fails($$select public.delete_book('wrong name')$$, 'exactly', 'deleting a book needs its name');
select public.delete_book('Babu');
select pg_temp.ok((public.whoami() -> 'books') = '[]'::jsonb, 'Babu''s book is gone');
reset role;

rollback;
