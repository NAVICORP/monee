# Pursee app: how the pieces fit (for everyone writing screens)

Read `docs/SPEC.md` first: it is the full feature list (a rebuild of Realbyte's Money Manager) and the style rules.

## Ground rules

- Flutter app in `app/`, Dart language 3.5 (pubspec `sdk: ^3.5.0`): no null-aware collection elements (`?x` in lists), no newer syntax. Flutter stable, Material 3. `withValues(alpha:)` is fine.
- **Nothing can be compiled here.** No Flutter SDK, no pub. CI compiles later. So write code you are sure of: check every constructor you call against its definition in this repo, every named parameter, every import path, null safety, `const` only where legal, `mounted` checks after `await` before using `context`. Prefer simple, boring Dart.
- Packages available (pubspec): http, shared_preferences, url_launcher, share_plus, path_provider, excel ^4, file_picker ^10, image_picker ^1, flutter_localizations. Nothing else.
- Style (Ishaque's rules, follow strictly):
  - Kuree's look: small and minimal text, fields and buttons; light theme; violet brand (`K.blue` is the violet).
  - Money colours always via `moneyColor()` / `MoneyText(kind:)`: income green, expense red, transfer grey.
  - Never native dropdowns or date pickers: use `showPicker`, `pickDate`, `pickPeriod`, `showKSheet`, `KChoice`.
  - No em dashes or middle dots in any UI text; no letter spacing. Use commas, colons, "to".
  - Text boxes, pills and chips sized to their content. Nothing spills out of its card.
  - Every list of things (transactions, accounts, groups, categories, tags, budgets, repeats, bookmarks, memos) has a delete option (with `confirm(... danger: true)`).
  - Errors: catch `ApiError` and show `e.message` with `toast(context, e.message, bad: true)` or a `Notice`.
- Screens that show money mix in `ReloadOnChange` (lib/ui/money.dart) and implement `Future<void> reload()`. After any successful save or delete, call `Me.instance.changed()` (or `changed(lists: true)` when accounts, groups, categories, tags or rates changed). Do not reload by hand elsewhere.
- Pages opened from a tab are pushed with `Navigator.of(context).push(MaterialPageRoute(...))` so the footer stays. Full-screen editors (a new transaction) use `Navigator.of(context, rootNavigator: true)`.

## Core (already written, do not change without saying so)

- `lib/core/api.dart`: `Api.instance` with `rpc(fn, [args])` (POST /rest/v1/rpc/fn, returns decoded JSON), `select(table, {columns, where, order, limit})` (PostgREST filters in `where`, e.g. `{'id': 'eq.$id'}`), `insert(table, row)`, `update(table, patch, {where})`, `delete(table, {where})`, `upload(bucket, path, bytes, contentType)`, `download(bucket, path)`, `signOut()`, `deleteAccount()`, `setPassword(p)`. `ApiError.message`.
- `lib/core/format.dart`: `Currency` (`format(v, {symbol, sign})`, `number(v)`, `decimals`, `name`, `symbol`), `kCurrencies`, `currencyOf(code)`, `money(v, code)`, `amountText(v, code)`, `toNum`, `rateText`, `isoDay`, `parseDay`, `dayOnly`, `addDays`, `dayLabel`, `dateLabel`, `shortDate`, `monthLabel`, `relativeDay`, `periodLabel`, `clock`, `stamp`, `dotDay`, `parseStamp`, `isoStamp`, `prettyPhone`, `phoneDigits`, `initials`, `csvCell`, `kMonths`, `kMonthsShort`, `kDaysShort` (Mon first).
- `lib/core/book.dart`: `Book` (settings and periods: `month(y,m)`, `monthOf(day)`, `week(day)`, `year(day)`, `weekdayNames`, `today`, `canEdit`, `isOwner`, `currency`, `main`), `Group`, `Account`, `Category`, `kGroupKinds`, `Txn` (a row of `txn_list`), and `Me.instance` (ChangeNotifier): `book`, `books`, `groups`, `accounts`, `liveAccounts`, `categories`, `tags`, `rates`, `version`, `load()`, `choose(bookId)`, `loadLists()`, `changed({lists})`, `reloadBook()`, `account(id)`, `category(id)`, `group(id)`, `topCategories(kind)`, `subsOf(id)`, `categoryPath(id)`, `rateOf(currency)`, `toMain(amount, currency)`, `email`, `phone`.
- `lib/ui/theme.dart`: `K` colours (`K.income`, `K.incomeBg`, `K.expense`, `K.expenseBg`, `K.transfer`, `K.chart` list of 14 colours, `K.blue` violet, `K.deep`, `K.ink`, `K.ink2`, `K.muted`, `K.border`, `K.border2`, `K.surface`, `K.surface2`, `K.paper`, `K.brand100..600`, `K.bad`, `K.badBg`, `K.warn`, `K.warnBg`, radii `K.rSm/rMd/r/rLg`, `K.shadow`), `Sp` spacing, `T` text styles (`display h1 h2 h3 amount body bodyStrong small tiny label button tabular`).
- `lib/ui/widgets.dart`: `KButton({label, onPressed, icon, kind: KButtonKind.primary|secondary|ghost|danger|blue, busy, expand, small})`, `KFab({label, icon, onPressed})`, `KCard({child, padding, onTap, color})`, `HeroCard({child, padding})`, `Pill(text, {color, fg, icon})`, `ProgressLine(value, {color, track, height})`, `KSegmented<V>({items: List<(V, String)>?, value, onChanged, expand})` (check its file for the items type before use), `RoundIcon(icon, {onTap, dark, tooltip, size, color})`, `EmptyState({icon, text, action})`, `Notice(text, {bad})`, `SectionTitle(text, {trailing, top})`, `KChoice({label, value, onTap, icon})`, `KField({label, controller, hint, keyboard, formatters, obscure, autofocus, maxLines, onSubmitted, onChanged, autofill, caps, prefix, suffix, enabled})`, `KSwitchRow({title, sub, value, onChanged})`, `Avatar(name, {size, color, fg})`, `Stat(value, label, {dark, big})`, `StatTile(value, label, {tone})`, `KRow({leading, title, sub, trailing, onTap, padding})`, `KGroup({children})`, `SearchField({controller, hint, onChanged})`, `showKSheet<R>(context, {title, builder, scroll})`, `PickOption<V>(value, label, {sub, icon, trailing})`, `showPicker<V>(context, {title, options, selected, search})` returns `PickOption<V>?`, `confirm(context, {title, text, yes, no, danger})`, `toast(context, text, {bad})`, `pickDate(context, {initial, first, last, title})`, `pickPeriod(context, {from, to, title})`, `GroupLabel(text)`, `LinkGroup(rows)`, `LinkRow(icon, text, onTap, {sub, value, bad})`, `KNavItem`, `KNavBar`, `Loading()`, `LoadFailed({message, onRetry})`, `PageBody({children, onRefresh, maxWidth, bottom})`, `MoneeIcon({size, shadow})`, `MoneeMark({size, color})`. Read the file for exact details before using one.
- `lib/ui/money.dart`: `moneyColor(countsAs)`, `MoneyText(amount, {currency, kind, style, sign, symbol, align})`, `PeriodKind {week, month, year, custom}`, `Period(kind, from, to)` with `Period.of(book, kind, day)`, `monthOf/weekOf/yearOf`, `step(book, n)`, `label(book)`, `contains(d)`, `args` (`{'date_from','date_to'}` strings), `PeriodBar({period, onChanged, trailing})`, `SummaryStrip({income, expense, total, carry})`, `PillTabs({labels, index, onChanged})`, `EmojiBadge(emoji, {name, size, color})`, `PercentPill(percent, {color})`, `BudgetBar({percent, todayPercent, height})`, `mixin ReloadOnChange`.
- `lib/ui/charts.dart`: `Slice(label, value, color)`, `PieChart({slices, height, maxLabels})`, `ChartPoint(label, value, {value2})`, `LineChart({points, height, color, color2, format})`, `BarChart({points, height, color, color2})`.
- `lib/ui/txn_list.dart`: `TxnRow(txn, {showDate, onTap, dim})` (tap opens `openEntry`), `DayHeader({day, income, expense})`, `TxnDayList({txns, upcoming, header, footer, empty, onRefresh})`.
- `lib/ui/book_gate.dart`: `pickCurrency(context, {selected, title, except})` returns a code; `guessTimezone()`.
- `lib/ui/shell.dart`: the four tabs, `TransPage`, `StatsPage`, `AccountsPage`, `MorePage` (each `const X({super.key})`).

## Who writes what (exported names are fixed; other code depends on them)

| Files | Exports (exact) |
|---|---|
| `lib/ui/trans/*.dart` | `class TransPage extends StatefulWidget { const TransPage({super.key}); }`, `Future<Map<String, dynamic>?> showFilter(BuildContext context, {required Period period, Map<String, dynamic>? current})` in `trans/filter.dart` (returns the filter json, `{}` for none, null when closed), `class SearchPage` in `trans/search.dart` |
| `lib/ui/entry/*.dart` | in `entry/entry_page.dart`: `Future<bool> openEntry(BuildContext context, {Txn? txn, String kind = 'expense', DateTime? day, Map<String, dynamic>? template, bool copy = false})` (true when something was saved or deleted); in `entry/calculator.dart`: `Future<num?> showCalculator(BuildContext context, {num? start, String? currency})` |
| `lib/ui/stats/*.dart` | `class StatsPage extends StatefulWidget { const StatsPage({super.key}); }` |
| `lib/ui/accounts/*.dart` | `class AccountsPage extends StatefulWidget { const AccountsPage({super.key}); }`, in `accounts/account_edit.dart`: `Future<bool> openAccountEditor(BuildContext context, {Account? account, String? groupId})`, in `accounts/account_page.dart`: `class AccountPage extends StatefulWidget { const AccountPage({super.key, required this.accountId}); final String accountId; }` |
| `lib/ui/more/*.dart` | `class MorePage extends StatefulWidget { const MorePage({super.key}); }`, in `more/passcode.dart`: `class PasscodeGate extends StatefulWidget { const PasscodeGate({super.key, required this.child}); final Widget child; }`, in `more/budgets.dart`: `class BudgetsPage extends StatefulWidget { const BudgetsPage({super.key}); }`, in `more/account_settings.dart`: `class AccountSettingsPage extends StatefulWidget { const AccountSettingsPage({super.key}); }`, in `more/categories.dart`: `class CategoriesPage extends StatefulWidget { const CategoriesPage({super.key, required this.kind}); final String kind; }`, in `more/currencies.dart`: `class CurrenciesPage extends StatefulWidget { const CurrenciesPage({super.key}); }` |

Use another group's export only by these names and signatures.

## The database (read the SQL for exact shapes)

`supabase/migrations/0001_books.sql` to `0007_grants.sql`. Tables (all filtered to the current book by row security, write with `Api.instance.insert/update/delete`): `books` (settings: update by owner), `book_members`, `account_groups`, `accounts`, `currency_rates`, `categories`, `tags`, `txns`, `txn_splits`, `txn_tags`, `txn_photos`, `repeat_rules`, `instalment_plans`, `budgets`, `bookmarks`, `day_memos`. New rows get `book_id` by default; never send it.

Functions (`Api.instance.rpc(name, args)`), args by name:
- `whoami()`, `create_book(name, currency, timezone, my_name)`, `delete_book(confirm_name)`, `delete_my_data()`, `set_main_currency(new_currency, per_old)`.
- `save_txn(p)`: p = `{id?, kind, at ('YYYY-MM-DDTHH:MM:SS'), account_id, to_account_id?, category_id?, amount, to_amount?, fee?, rate?, note?, description?, splits?: [{category_id, amount, note}], tags?: ['name']}` returns `{id, at, rate, to_amount}`. With `id` it updates (only keys present change).
- `add_instalments(p, months)`, `add_repeat(p, freq ('day'|'week'|'month'|'year'), every, ends_on)`, `catch_up()`, `upcoming(date_from, date_to)` (list of `{repeat_id, day, kind, account_id, to_account_id, category_id, amount, note, amount_main}`).
- `card_status(card)` -> `{debt, payable, outstanding, cycle_from, next_settlement, due, overdue, billing_account_id, auto_pay}`, `pay_card(card, amount?, from_account?, at?)`.
- `period_totals(date_from, date_to, f)` -> `{income, expense, carry, carry_over, total}`.
- `day_totals(date_from, date_to, f)` -> `[{day, income, expense}]`.
- `span_totals(date_from, date_to, unit ('week'|'month'), f)` -> `[{from, to, income, expense}]` newest first.
- `txn_list(date_from, date_to, f, max_rows)` -> rows for `Txn`.
- `note_totals(date_from, date_to, kind, f)` -> `[{note, count, total}]`.
- `category_totals(date_from, date_to, kind, parent?, f)` -> `{total, rows: [{category_id, key, name, emoji, amount, percent, has_subs}]}`.
- `category_trend(kind, category?, months, until?, f)` -> `[{year, month, from, to, amount}]` oldest first.
- `budget_status(date_from, date_to, period)` -> `{from, to, today_percent, total: {budget, spent, left, percent} | null, rows: [{category_id, name, emoji, budget, spent, left, percent}]}`.
- `accounts_overview(include_deleted)` -> `{currency, today, assets, liabilities, total, missing_rates, groups: [{id, name, emoji, kind, hidden, collapsed, deleted, total_main, payable_main, outstanding_main, accounts: [{id, name, currency, balance, balance_main, in_totals, hidden, deleted, card: card_status|null, debit: {linked_account_id, spent_this_month}|null}]}]}`.
- `balance_at(account, until)`, `account_trend(account, months)` -> `[{year, month, from, to, in, out, balance}]`, `asset_trend(months)` -> `[{year, month, to, assets, liabilities, total}]`.
- `period_accounts(date_from, date_to)` -> `{expense_cash, expense_card, transfer_out, expense_before, compared_percent, days}`.
- `import_rows(rows)` rows `[{date, kind, account, to_account, category, subcategory, amount, to_amount, currency, rate, note, description}]` -> `{imported, accounts_made, categories_made}`.

Filters `f`: `{accounts: [uuid], categories: [uuid], kinds: [..], tags: [names], q: text, min, max}`; `{}` for none.

Dates go as `isoDay(d)` strings; timestamps as `isoStamp(d)`.
