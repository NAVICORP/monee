# Pursee

Your money in one book, on every device: income, expenses and transfers; daily, calendar, monthly and total views; stats by category; accounts with cash, bank, wallets, credit and debit cards, savings, investments and loans; budgets; repeats and instalments; many currencies; tags, notes and receipt photos; a passcode; Excel export and import. A rebuild of Realbyte's Money Manager in SkiFi's own style, with sync and shared books (see `docs/SPEC.md`).

One Flutter app for Android, iPhone and the web (pursee.skifi.co/app), on SkiFi's own server.

## What is where

| Folder | What |
| --- | --- |
| `app/` | The Flutter app. `lib/core` talks to the server and holds the book, `lib/ui/trans`, `stats`, `accounts`, `more` are the four tabs, `lib/ui/entry` adds and edits a transaction, `lib/ui/start` signs in. `docs/APP_CONTRACT.md` says how the pieces fit. |
| `supabase/migrations/` | The database: books and people, accounts and groups, categories, transactions (with splits, tags and photos), repeats, instalments, cards, budgets, and every report the screens read. All the arithmetic lives here. |
| `supabase/tests/` | `monee_test.sql` runs it all as the people who use it (an owner, another book's owner, a viewer) and checks every rule. |
| `server/site.mjs` | The site in front of the API: the plain pages, the web app at `/app/` (with its offline shell), and the API door. |
| `web/` | The plain pages: home, privacy, terms, support, delete account. |
| `deploy/` | The Dokploy compose file. |
| `tools/` | `demo.sql` (a year in a demo book), `dbtest.sh` (the database tests on any Postgres), `brand/brand.py` (the logo and every icon). |
| `docs/` | `SPEC.md` (what Pursee is), `APP_CONTRACT.md` (the app's shared code and the database calls), `RELEASE.md` (server and stores). |

## How it fits together

- **Sign-in** is SkAuth at account.skifi.co (WhatsApp code, email code, or password), passed through by the shared SkiFi app base.
- **Books.** Anyone who signs in starts a book and owns it. Others join a book as editors or viewers when the owner adds their email or WhatsApp number. Every table carries `book_id`, and row security keeps each book's people inside it. The app names the book in every request (the `x-farm-id` header, the one the app base passes to the database).
- **Money** has one source of arithmetic: the views `account_moves` (what each transaction does to each balance) and `entries` (what counts as income and expense after the book's rules: card spending as a lump on payment day, Transfer-Expense accounts, transfer fees). Every total, chart and budget reads them.
- **Currencies.** Each account keeps its own currency; each transaction keeps the rate it was entered at, so old months never change when today's rate does.
- **Repeats and card payments** are recorded by `catch_up()`, which the app calls when it opens. Running it twice records nothing twice.

## Checks

Every push runs, on GitHub Actions:

- **Server**: the migrations on a fresh Postgres, `monee_test.sql`, the demo book, and the site script. Dokploy builds the server image itself from `main` (the Dockerfile builds the web app first).
- **App**: `flutter analyze` and the tests, the web build opened in a real browser, a release APK. iOS on request.

On your own Postgres: `PGHOST=... PGUSER=... tools/dbtest.sh`.

## Changing the database

- New changes go in a new migration file, never into an old one that has run on the server.
- A migration that adds functions ends with its own `revoke execute ... from public, anon, authenticated` and the grants it needs (see `0007_grants.sql`).
- Add the checks to `monee_test.sql` in the same change.
