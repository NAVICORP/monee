# Pursee: our money manager, rebuilt from Realbyte's Money Manager

Pursee is SkiFi's own personal money app, modelled feature for feature on Realbyte's Money Manager (Google Play id com.realbyteapps.moneymanagerfree). Same features, our stack, our Kuree/Dairee style, in violet.

## Decisions (2 Nov 2026)

- **Name:** Pursee.
- **Colour:** violet.
- **Data:** on our server, sign-in through SkAuth (account.skifi.co). Same data on Android, iPhone and web.
- **1.0 scope:** everything Money Manager has. Our web app takes the place of their PC Manager.
- **Pricing:** free, no ads for now. Pro can come later.
- **Built like Dairee:** one Flutter app for Android, iPhone and web, Postgres, the shared SkiFi app base, Dokploy.
- **Proposed, not yet confirmed:** pursee.skifi.co (first monee.skifi.co), bundle id co.skifi.pursee, repo NAVICORP/monee.

Don't copy their name, logo, icons, colours, help text or screenshots. Same features, our own design.

---

## 1. Teardown: what Money Manager is

**Who:** Realbyte Inc., Seoul. On iOS since 2012 and Android since 2013. 10M+ Play installs, 4.6 stars from about 468K reviews, Editors' Choice. Ishaque's phone has version 4.13.1 of the Android app.

**How they make money:**
- Android: free with ads. The free version caps assets at 15. The paid version removes ads, lifts the cap and unlocks PC editing over Wi-Fi.
- iOS: a separate "Remove Ads" app at $5.99, plus a Data Sync subscription at $2.49 a month or $19.99 a year.
- Third-party estimate (AppGoblin): about 428K monthly active users and $50K+ a month, 59% from ads and 41% from purchases.

**Latest additions:** 4.13 tags on transactions (searchable). 4.12 three Quick-Add home screen widgets, theme and transparency options. 4.10 swap From/To on transfers, collapsible account groups, copy a transaction with today's date or its own date, several photos at once. 4.9 editable and refreshable exchange rates, main and sub currency shown together. 4.8 tablet landscape, "Edit all dates", "Edit all notes", clear autocomplete history. 4.7 Note tab.

### Navigation

Four footer tabs: **Trans.**, **Stats**, **Accounts**, **More**. A round coral "+" floats on the Trans. tab. The free version shows an ad banner above the footer.

### Trans. tab

- **Header:** `< Oct 2026 >` month switcher, then Bookmarks (star), Search, Filter.
- **Sub-tabs:** Daily, Calendar, Monthly, Total, Note.
- **Summary strip** under the sub-tabs: Income (blue), Expenses (red), Total.
- **Daily:** grouped by day. Each day header has a big date, a weekday chip, month.year, the day's income and expense. Each row: category emoji and name with the subcategory under it, the account (or "From → To" for transfers) with the note inline, and the amount in the account's own currency (income blue, expense red, transfer neutral).
- **Calendar:** month grid, Sunday in red, Saturday in blue. Each day shows income, expense and net. Days of the next and previous months are dimmed, today is highlighted, and upcoming repeat entries show dimmed. Tapping a day opens its list, where a record or a memo can be added.
- **Monthly:** `< 2026 >`. Year totals at the top, then each month with income, expense and net. The current month opens into its weeks with the current week highlighted. Future months already show scheduled repeats.
- **Total:** a **Budget** block (Budget Setting button, Total Budget and one bar per category with % used, spent, and either what's left or "Excess", with a "Today" marker showing how far into the month we are), then an **Accounts** block for the period (expenses compared with last month in %, expenses from cash and bank, expenses on cards, transfers out of cash and bank) and **Export data to Excel**.
- **Note:** transactions grouped by their note text, with count and total.
- **Filter:** Income and Expenses rings with the % selected, Total. Tabs Income, Expenses, Account. Checkbox lists by group; each account shows Income/Transfer-in and Expenses/Transfer-out for the period.
- **Search:** text, amount and tags.
- **Bookmarks:** saved entries for frequent income, expenses and transfers.

### Adding a transaction

- Type switch: Income, Expense, Transfer.
- Fields: Date (with Rep/Inst.), Account, Category and subcategory, Amount (calculator keypad), Note, Description, several photos, tags.
- Transfer: From, To, Amount, Fees, swap button.
- "Continue" saves and opens a fresh entry. Copy keeps the original date or uses today.
- Sub currency accounts show the main currency amount alongside, with an editable rate.
- **Repeat:** records automatically on the date.
- **Instalment:** pick the number of months; the amount is split and shown as "n of N" with the remaining balance.

### Stats tab

- `< Oct 2026 >` with a period menu: Weekly, Monthly, Annually, Period, plus List and Trend.
- Income | Expenses tabs with totals.
- Pie chart with callout labels (emoji, name, %), then a list: coloured % pill, category, amount.
- Tapping a category opens a line chart of that category over time with its transactions.
- Budget and Note views; Note sorts by name, count or amount.

### Accounts tab

- Header: Accounts, a chart button (asset trend graphs) and a menu.
- Strip: Assets (blue), Liabilities (red), Total.
- Groups with emoji and a group total in the main currency, accounts underneath with balances in their own currency (positive blue, negative red, zero grey). Groups collapse.
- The Card group shows two columns per card: Balance Payable and Outstanding Balance.
- Tapping an account opens its transactions by month and its balance trend.

### More tab

Grid: Configuration, Accounts, Passcode, CalcBox, PC Manager, Backup, Feedback, Help, Recommend, Remove Ads. Version number at the top.

- **Configuration > Category/Repeat:** Income Category Setting, Expenses Category Setting, Subcategory (on/off), Budget Setting, Tag Settings, Repeat Setting.
- **Configuration > Configuration:** Main Currency, Sub Currency (several), Start Screen (Daily or Calendar), Monthly Start Date, Weekly Start Day, Carry-over (on/off). Style (theme) is in settings too.
- **Accounts:** Account Group, Accounts Setting, Deleted account group, Deleted accounts, Transfer-Expense setting, Card expenses display config ("At the time" or lump sum).
- **Passcode:** with a delay before it asks again.
- **Backup:** Excel backup and restore, automatic backup, moving to a new phone, bulk import from Excel (also with sub currencies), photo backup.
- **PC Manager:** the phone serves a web page over the same Wi-Fi; edit and sort by date, category or account group, with charts. (Pursee's web app replaces this.)

### Rules worth copying exactly

1. **Every income and expense moves an account.** Transfers move money between accounts and are not income or expense, unless the destination is marked **Transfer-Expense** (only savings, insurance, investment and loan accounts, never cash, bank, card or debit card); then the transfer counts as an expense.
2. **Credit cards** have a billing account, a settlement day and a payment day. Spending up to the settlement day is the **payable** balance; spending after it is **outstanding**. On the payment day the payable amount moves from the billing account to the card, by the Pay button or automatically if Automatic Payment is on. A card payment is a transfer from bank to card. Overdue amounts show in grey.
3. **Card expense display:** "At the time" (default: every card spend is an expense on its own date) or lump sum (card spends turn into one expense on the payment date).
4. **Debit cards** are linked to a bank account; spending comes off that account straight away.
5. **Repeats** record themselves on the date. Repeat Setting decides whether upcoming entries appear on their date or from the first day of the month. **Instalments** are accrual: $300 over 3 months from 12 Feb shows $100 on 12 Feb, 12 Mar and 12 Apr.
6. **Carry-over** adds last month's balance into the Trans. tab totals. The Accounts tab always shows the running balance.
7. **Month start day** and **week start day** drive every period view, the calendar and budgets.
8. **Multi-currency:** each account has its own currency; totals are in the main currency at a stored rate that can be edited or refreshed.
9. Accounts can be **hidden**, **left out of totals**, deleted and **restored**.
10. **Budgets** per category and in total; weekly, monthly or yearly.

### What their users complain about (Pursee's edge)

| Complaint | Pursee |
|---|---|
| No sync between devices; a partner can't see the same book | Server sync through SkAuth; shared books with family later |
| No split transactions (one shop, several categories) | Split a transaction across categories |
| More and more ads | No ads |
| No April to March financial year view | Financial year period option |
| New entries always start on today's date | Option to keep the last used date |
| Hard to learn at first | Starter groups and categories, short first-run guide |

---

## 2. Pursee: what we build

### Look and feel (as Kuree and Dairee)

- Violet palette, Kuree's small, minimal text, fields and buttons, deep stadium buttons, modern curvy pickers and dropdowns (no native controls), consistent icons.
- Footer: Trans, Stats, Accounts, More. It stays visible on opened screens too. Wide screens get a side bar (like Dairee).
- Light and dark themes. Income, expense and transfer each get one fixed colour across the app.
- Languages as in Kuree: English, Arabic (right to left), Malayalam, Tamil, Kannada, Hindi. Language changes only from Settings. Minimal Indian-language fonts (Manjari for Malayalam).
- Admin-style delete on everything: transactions, accounts, groups, categories, tags, bookmarks, budgets, repeats.

### Screens

1. **Sign-in** through account.skifi.co; first run creates a book with starter groups (Cash, Bank, Card, Debit card, Savings, Investments, Loan, Insurance, Others), categories and the main currency.
2. **Trans:** Daily, Calendar, Monthly, Total, Note; month switcher, bookmarks, search, filter.
3. **Add/edit transaction** sheet with calculator keypad, repeat and instalment, split, photos, tags, sub currency rate, Continue, Copy.
4. **Stats:** period menu, Income/Expenses, pie with labels, list, category trend, budget view, note view.
5. **Accounts:** assets, liabilities, total; groups; card columns; account detail with monthly list and trend; asset trend charts.
6. **More:** Configuration, Accounts settings, Categories, Budgets, Tags, Repeats, Currencies, Passcode, Calculator, Export/Import (Excel), Backup, Feedback, Help, Share.
7. **Home screen widgets** (Quick-Add) after 1.0's core is done.

### Data model (Postgres)

| Table | Holds |
|---|---|
| `book` | owner, name, main currency, month start day, week start day, start screen, carry-over, subcategories on, card display mode, repeat timing, financial year start |
| `book_member` | who can see or edit a book (owner only in 1.0; shared books later) |
| `currency_rate` | book, currency, rate to main, updated at |
| `account_group` | book, name, emoji, kind (cash, bank, card, debit_card, savings, investment, loan, insurance, prepaid, overdraft, other), order, hidden, deleted_at |
| `account` | group, name, currency, opening balance, note, in_totals, hidden, transfer_as_expense, order, deleted_at; card: billing_account, settlement_day, payment_day, auto_pay; debit: linked_account |
| `category` | book, kind (income or expense), parent (subcategory), name, emoji, order, deleted_at |
| `tag` | book, name |
| `txn` | book, kind (income, expense, transfer, card_payment), at (date and time), account, to_account, category, amount, fee, currency, rate, note, description, repeat, instalment number, split parent, created_by |
| `txn_tag`, `txn_photo` | links and stored photos |
| `repeat_rule` | template, frequency, interval, start, end, next run |
| `instalment_plan` | total, months, first date |
| `budget` | book, category (empty means total), period, amount, from month |
| `bookmark` | saved template entries |
| `day_memo` | date, text, colour |

Balances, card payable and outstanding, carry-over and budgets are worked out in the database (views and functions), tested in `supabase/tests`, like Dairee.

### Stack (same as Dairee)

- Flutter app in `app/` for Android, iPhone and web; web app at pursee.skifi.co/app (first at monee.skifi.co, which now redirects there).
- Postgres migrations in `supabase/migrations`, DB tests on every push.
- Shared SkiFi app base image, sign-in through SkAuth, Dokploy compose `monee` on deploy.skifi.co.
- CI: analyse, tests, screen pictures from a demo book, web build, Android APK, iOS on request.
- Demo book for screenshots and store review: a Gulf expat with SAR, INR and BHD accounts, wallets, bank, two cards, savings, a year of history, budgets and repeats.
- Landing page in Kuree's kureeapp.com layout, in violet.

### Build order

1. Repo, server and database: data model, balance and card logic, DB tests, demo book, deploy.
2. Accounts and categories, add/edit transaction, Daily, Accounts tab.
3. Calendar, Monthly, Total, Note, filter, search, bookmarks.
4. Stats and budgets.
5. Cards, debit cards, Transfer-Expense, repeats and instalments, carry-over, multi-currency.
6. More: settings, passcode, calculator, Excel export and import, backup, tags, photos, split.
7. Landing page, store listings, review account, widgets.

---

## Sources

- [Google Play listing](https://play.google.com/store/apps/details?id=com.realbyteapps.moneymanagerfree)
- [Realbyte site](https://realbyteapps.com) and [Help Center](https://help.realbyteapps.com)
- Help: [Home tab](https://help.realbyteapps.com/hc/en-us/articles/360043325533-Home-tab), [Stats tab](https://help.realbyteapps.com/hc/en-us/articles/360042842734-Stats-tab), [Add income and expense](https://help.realbyteapps.com/hc/en-us/articles/360043325233-How-to-add-an-income-expense), [Transfers](https://help.realbyteapps.com/hc/en-us/articles/360042842254-How-to-record-a-transfer), [Repeat and instalment](https://help.realbyteapps.com/hc/en-us/articles/360046668993-How-to-set-up-a-repeat-schedule-installment), [Transfer-Expense](https://help.realbyteapps.com/hc/en-us/articles/360042889454-How-to-set-up-savings-investment-insurance-loan-as-an-expense), [Card settlement](https://help.realbyteapps.com/hc/en-us/articles/360015963554-How-to-settle-credit-card-payments), [Card dates](https://help.realbyteapps.com/hc/en-us/articles/360015963594), [Card expense display](https://help.realbyteapps.com/hc/en-us/articles/360045129073-How-to-display-credit-card-usage-amount), [Debit cards](https://help.realbyteapps.com/hc/en-us/articles/360016071953-How-to-use-debit-cards), [Carry-over](https://help.realbyteapps.com/hc/en-us/articles/360043218993-How-to-turn-on-carry-over-feature), [PC Manager](https://help.realbyteapps.com/hc/en-us/articles/360043758513-How-to-use-PC-Manager)
- [App Store listing](https://apps.apple.com/app/id560481810) and [Remove Ads app](https://apps.apple.com/us/app/id564730202)
- [AppGoblin estimates](https://appgoblin.info/apps/com.realbyteapps.moneymanagerfree)
- [Community notes on the PC Manager's web endpoints](https://glama.ai/mcp/servers/@shahlaukik/money-manager-mcp/blob/164ddfe40b238d5001f2d41721fd4c1ebd723c62/docs/technical/API_DOCUMENTATION.md)
- Ishaque's own screenshots of the app (Android, version 4.13.1), 2 Nov 2026
