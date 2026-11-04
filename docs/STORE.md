# Pursee: store listing

Everything to paste into Google Play Console and App Store Connect. The screen pictures come from the `store-pictures` branch and are also served at https://pursee.skifi.co/assets/store/play/ (so the store consoles can fetch them) (drawn in CI from the demo book, so no real names are shown).

## Both stores

- App name: **Pursee: Money Manager** (App Store Connect confirms it is free when the app is made; fallback **Pursee: Budget and Expenses**)
- Developer: SkiFi (SKIFI GROUP LLC)
- Category: **Finance** (App Store secondary: Productivity)
- Website: https://pursee.skifi.co
- Support: https://pursee.skifi.co/support, contact@skifi.co, +91 78270 87878
- Privacy policy: https://pursee.skifi.co/privacy
- Terms: https://pursee.skifi.co/terms
- Account deletion: https://pursee.skifi.co/delete-account (also in the app: More > Delete my account)
- Price: free, no in-app purchases, no ads
- Copyright: 2026 SKIFI GROUP LLC

| | |
|---|---|
| Google Play app | Pursee, package co.skifi.pursee |
| App Store app | Pursee, bundle co.skifi.pursee, SKU pursee |
| Play link once live | https://play.google.com/store/apps/details?id=co.skifi.pursee |

**Subtitle** (App Store, 30 max)

```
Expenses, budgets and accounts
```

**Promotional text** (App Store, 170 max)

```
Every income, expense and transfer in one book, on your phone and your computer. Cards, budgets, repeats and every currency you use. Free, with no ads.
```

**Short description** (Google Play, 80 max)

```
Track spending, accounts, cards and budgets. Same book on phone and computer.
```

**Keywords** (App Store, 100 max)

```
money manager,expense,budget,spending,account book,finance,salary,credit card,currency,bills
```

**Full description** (the same text on both stores)

```
Pursee is a money book for everything you earn, spend and move: cash, bank, cards, wallets, savings and loans, in every currency you use.

It keeps the record. Pursee never connects to your bank and never moves money.

EVERY DAY IN ONE LOOK
- A home page with your net worth, this month's income and spending, and where the money went.
- Daily, Calendar, Monthly and Total views of the month.
- Income, expenses and the total for every day, week and month.
- Search by note, amount or tag, and filter by category or account.

ADD AN ENTRY IN SECONDS
- Income, expense or transfer, with a calculator built in.
- Categories with subcategories, notes, tags and photos of the receipt.
- Split one bill across several categories, or pay it partly in cash and partly by card.
- Save frequent entries as bookmarks.

CARDS THAT ADD UP
- Credit cards with a settlement day and a payment day.
- See what is payable now and what is still open, and pay the card in one tap, or let it pay itself.
- Debit cards spend straight from their bank account.

REPEATS AND INSTALMENTS
- Salary, rent and bills record themselves on the day.
- Split a big purchase into monthly instalments.

BUDGETS AND STATS
- A budget for the month and for each category, with how far into the month you are.
- Pie charts by category, trends over time, and spending by note.

EVERY CURRENCY YOU USE
- Each account keeps its own currency; totals are in your main currency at the rate you set.

ON YOUR PHONE AND YOUR COMPUTER
- The same book on Android, iPhone and the web at pursee.skifi.co.
- Share a book with your family: they can add entries or just look.
- Lock the app with a passcode, and switch on night mode.
- Export to Excel any time, and bring your records over from another money app's Excel backup.

Sign in with a code on WhatsApp or by email. Delete your account any time from More.

Privacy: https://pursee.skifi.co/privacy
Terms: https://pursee.skifi.co/terms
```

**What's new** / release notes for 1.0.0

```
The first release of Pursee: daily, calendar and monthly views, accounts and cards, budgets and stats, repeats and instalments, every currency, Excel export and import, and the web app.
```

## Google Play

- App category: Finance. Tags: Finance, Productivity.
- Contains ads: No. Advertising ID: No. In-app purchases: No.
- Target audience: 18 and over.
- Content rating: all other app types; no ratings-relevant content, no user content sharing, no online content, nothing age-restricted, no location sharing, no digital purchases. Result: Everyone / All ages.
- Financial features: in the Financial features declaration choose **None of the above** (or "Other" with the text below if the form insists): Pursee is a personal record of a person's own income and spending. It is not a bank, does not connect to accounts, and does not process, move or lend money.
- Government app: No. Health features: none.
- Data safety: nothing shared; encrypted in transit; account created with username, password and other authentication; deletion at https://pursee.skifi.co/delete-account.

| Data | Required | Why |
|---|---|---|
| Name | Yes | App functionality, account management |
| Email address | No (a phone number works instead) | App functionality, account management |
| Phone number | No (an email works instead) | App functionality, account management |
| Other financial info (the person's own records of income, spending and balances) | Yes | App functionality |
| Photos (receipt photos the person adds) | No | App functionality |
| Other user-generated content (notes, tags, memos) | No | App functionality |

## App Store

- Age rating: every question None or No, giving 4+.
- App Privacy: Data used to track you: none. Data linked to you, all for App Functionality: Contact info (name, email address, phone number), Financial info (other financial info), User content (photos, other user content).
- Export compliance: no non-exempt encryption (ITSAppUsesNonExemptEncryption is false in Info.plist).
- Pricing: free, all countries and regions except China mainland.

## YouTube intro video (for Play's Video field)

Video (1920 x 1080, 37 s) and thumbnail (1280 x 720): `tools/store/video.cjs` and `tools/store/music.py` (the music is made from sine waves, nothing to license). Upload to the SkiFi Creative Hub channel as Public or Unlisted, not made for kids, then put the link in Play's store listing under Video.

**YouTube title**

```
Pursee: your money, in one book
```

**YouTube description**

```
Pursee is a money book for everything you earn, spend and move: cash, bank, cards, wallets, savings and loans, in every currency you use.

See your net worth and this month at a glance, add an entry in seconds, split a bill or pay part cash and part card, know what your card owes and when, and see where it all goes with budgets and charts. Night mode included.

Free on Android, iPhone and the web: https://pursee.skifi.co
```

## The review account

Both stores sign in with the same account Kuree's and Dairee's reviewers use: **contact@skifi.co** with its review password (the owner types it in; it is never written down here). Sign in with Email > Use a password. That account owns a sample book, **My money**, with a year of made-up income, spending, cards and currencies (supabase/migrations/0009_review_book.sql). It is linked the first time that account signs in to Pursee. To delete the account: More > Delete my account (please don't, on the review account).

Review notes (both stores):

```
Sign in with Email, then Use a password, with the account below. It opens "My money", a sample book with a year of made-up income, spending, accounts and cards.

Pursee is a personal record of a person's own money: income, expenses, transfers between their own accounts, budgets and stats. It does not connect to banks and never takes, moves or lends money.

Delete account: More, then Delete my account.
```
