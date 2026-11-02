-- Who may call which function.
--
-- Everything is closed first, then opened one by one. The platform's defaults
-- open every new function to the API roles, so a later migration that adds
-- functions must end with its own revoke and grants, the same way.

revoke execute on all functions in schema public from public, anon, authenticated;

-- Used inside row policies, column defaults, triggers and the views, which run
-- as the person writing: they need to be callable, and each checks who is asking.
grant execute on function
  public.clean_email(text), public.my_phone(), public.my_email(), public.requested_book(), public.trusted_writer(),
  public.book_now(uuid), public.book_today(uuid), public.current_book_id(), public.my_role(), public.can_edit(),
  public.is_owner(), public.my_name(), public.group_kind(uuid), public.account_kind(uuid), public.rate_of(uuid, text),
  public.month_day(date, int), public.last_settlement(int, date), public.due_after(int, date),
  public.repeat_date(public.repeat_rules, int), public.repeat_dates(public.repeat_rules, date, date),
  public.uuids(jsonb), public.texts(jsonb)
  to authenticated;

-- The app.
grant execute on function
  public.whoami(), public.create_book(text, text, text, text), public.delete_book(text), public.delete_my_data(),
  public.set_main_currency(text, numeric),
  public.save_txn(jsonb), public.add_instalments(jsonb, int), public.add_repeat(jsonb, text, int, date),
  public.catch_up(), public.upcoming(date, date), public.card_status(uuid), public.pay_card(uuid, numeric, uuid, timestamp),
  public.month_range(uuid, int, int), public.period_totals(date, date, jsonb), public.day_totals(date, date, jsonb),
  public.span_totals(date, date, text, jsonb), public.txn_list(date, date, jsonb, int),
  public.note_totals(date, date, text, jsonb), public.category_totals(date, date, text, uuid, jsonb),
  public.category_trend(text, uuid, int, date, jsonb), public.budget_status(date, date, text),
  public.balance_at(uuid, date), public.accounts_overview(boolean), public.account_trend(uuid, int),
  public.asset_trend(int), public.period_accounts(date, date), public.import_rows(jsonb)
  to authenticated;

-- The views are read through row level security (security_invoker).
revoke all on public.account_moves, public.txn_lines, public.entries from anon;
revoke insert, update, delete on public.account_moves, public.txn_lines, public.entries from authenticated;

-- The API never needs these, and TRUNCATE would pass by row level security.
revoke truncate, trigger, references on all tables in schema public from public, anon, authenticated;
