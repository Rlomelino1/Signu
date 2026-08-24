# Signu

A subscription tracker for Brazilian bank and card data. Signu reads your bank and
card transactions through Open Finance, works out which of them are recurring, and
shows you what you are paying for and when the next charge lands. The name is from
*assinatura* — subscriptions are things you signed.

## What you can do in it

The app answers one question — *what am I paying for every month, and when does the
next charge land?* — from real transaction data rather than from receipts or manual
entry. Nothing is typed in by hand. You connect a bank, and the subscriptions appear.

- **Connect a bank or card** through the Open Finance consent flow, and connect more
  than one. Removing a link later does not take your history with it.
- **See what you are paying for.** Every subscription Signu is confident about is
  listed with its amount, its cadence and its next expected charge date.
- **Confirm the uncertain ones.** Where the data is suggestive rather than conclusive,
  Signu asks instead of deciding — *Track it* or dismiss, in a review queue.
- **Follow a subscription over time.** Each one has a detail screen with its charge
  timeline, its price history, and a *Mark cancelled* action for when you cancel it
  with the merchant.
- **Make it yours.** Rename a subscription or a bank account, categorise it, or hide
  one you do not want tracked.
- **Get reminded.** Turn on a reminder per subscription and Signu emails you before
  the charge lands.
- **See the month ahead** in a calendar view, and search across everything.
- **Leave.** Delete a connection, or delete the account and all of its data, from
  Settings.

## Stack

- **Supabase** — Postgres for the data, Edge Functions for everything the app is not
  allowed to write itself, Auth for sign-in (email + password and Google), and
  `pg_cron` for the daily sync and the reminder mail.
- **Pluggy** — the Brazilian Open Finance aggregator that supplies the bank and card
  data, reached through its Connect widget and its data API.
- **SwiftUI** — the iOS app, Swift 6 language mode, with its own small design system.
  Unit tests in Swift Testing, UI tests in XCTest.
- **Deno / TypeScript** — the Edge Functions and the detection engine they run.
- **GitHub Actions + the Supabase CLI** — three required checks on every PR (the iOS
  build and its tests, the detection tests, and a from-scratch schema apply), and a
  deploy to production on green merges to `main`.
- **Python** — a few standalone harnesses used when developing against real data.

## Repo layout

```
backend/
  supabase/
    migrations/    versioned SQL, forward-only
    functions/     the Edge Functions, over a shared pure core in _shared/
    templates/     the two auth emails
    tests/         pgTAP suites
  *.py             data harnesses
frontend/
  Signu/           the iOS app — Data/, DesignSystem/, Features/, Models/
  SignuTests/      unit tests
  SignuUITests/    UI tests
  Tools/           build and install scripts
.github/workflows/ci.yml
```

## Running it

```sh
# iOS
xcodebuild build -project frontend/Signu.xcodeproj -scheme Signu \
  -configuration Debug -destination 'generic/platform=iOS'

# backend
deno test backend/supabase/functions/_shared/
deno lint backend/supabase/functions
```

The app reads its project URL and keys at launch from `frontend/Signu/Config.plist`,
which is not committed — copy `frontend/Signu/Config.example.plist` and fill it in.

## Where the design reasoning lives

This README is an overview and nothing more. The specification is the source of
truth: a living document with a changelog, carrying the full schema, the detection
doctrine, every screen contract, and the reasoning behind the decisions — including
the ones that were rejected and why. It is kept alongside the design references and
the archive of everything this README used to say, outside version control. Where
this README and the specification disagree, the specification wins.

Anything not covered there is answered by the code.
