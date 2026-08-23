# Ceres

Ceres is an Android app for tracking food, activity, weight, water, and
sleep — built to show the full picture of a day instead of a single number,
and to never present an estimate as if it were a measurement.

## What it does

- **Meals** — search a catalog (Argentine foods, USDA, Open Food Facts by
  barcode), describe what you ate in plain text or out loud, or take a photo. AI
  estimates the items; you always review and confirm before anything is saved.
  Dietary preferences, allergies and conditions are part of the profile and
  constrain what the app is allowed to suggest you eat.
- **Activity** — MET-based calorie estimation with an adjustable exercise
  credit, plus manual entry for anything else.
- **Weight, body measurements, water, and sleep** — logged per day, editable
  and deletable at any time, for any date.
- **Day context** — sick days (with severity and a note), planned rest days,
  and alcohol (by drink format, counted in 10 g standard units). None of it
  changes a single calculation: it exists so a gap in the activity chart can be
  read for what it was. See [`docs/contexto-diario.md`](./docs/contexto-diario.md).
- **Progress** — trends over time, plus a full day-by-day history, and a PDF
  report of any period you can keep or hand to a professional.
- **Pals** — share your day with people you choose. Meals and whether you
  moved are always visible to an accepted pal; photos, water, sleep, and
  exercise detail are each off by default and only shared if you turn them on.
- Automatic cloud backup, account sync across devices, and in-app
  self-updates (the app isn't distributed through the Play Store).

## Stack

Flutter (Android) · Supabase (Postgres with row-level security, Auth,
Storage, Edge Functions) · Gemini for photo/text meal analysis · USDA
FoodData Central and Open Food Facts for the food catalog.

## Status

Actively developed and in daily use. [`ESTADO.md`](./ESTADO.md) (Spanish)
tracks current state and what's next; [`docs/estado-de-la-app.md`](./docs/estado-de-la-app.md)
has the detailed feature-by-feature status.

## Running it

```bash
flutter pub get
flutter run                                        # local mode: no login, nothing leaves the device
flutter run --dart-define-from-file=env/local.json  # against a real Supabase project
flutter test
```

Without `env/local.json` the app runs entirely offline against local storage —
enough to clone the repo and run it, or run the test suite, with no
credentials at all.

### On the emulator

Boots the `ceres` AVD, waits for it, and installs the app on it:

```bash
flutter emulators --launch ceres
adb wait-for-device shell 'while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done'
flutter run -d emulator-5554                                       # demo mode
flutter run -d emulator-5554 --dart-define-from-file=env/local.json  # your real account
```

Prefer the first one for poking at the app: no credentials, no login, and
"Probar sin cuenta" seeds a full day plus 30 days of history — none of which
touches a real account. The seed only happens in a debug build compiled
without a server (see [`docs/estado-de-la-app.md`](./docs/estado-de-la-app.md#datos-de-ejemplo)).

If the AVD doesn't exist yet, `flutter emulators --create --name ceres`
makes it. `flutter emulators` lists what's available and `adb devices` shows
whether it finished booting (`device`, not `offline`). Once `flutter run` is
attached, `r` hot-reloads, `R` restarts, and `q` quits.

## The professional panel

A separate web app, in [`backoffice/`](./backoffice/), for a nutritionist to
follow someone's day-to-day. It reads only what the user granted, per category
and revocably, and the patient's data is read-only.

The one thing it writes is the professional's own notes, in a table of their
own. **Those notes are private to whoever wrote them** — they never appear in
the patient's app, not even the ones about them.

```bash
cd backoffice
npm install
npm run dev          # http://localhost:3000
npm test             # node --test, no extra dependencies
```

Every count, average, streak and percentage is computed over the **effective
period**: the overlap between the window you picked and the time the person has
actually been using the app. Someone who started on the 18th logged 13 of 13
days, not 13 of 30. The same formula lives in three places that must agree —
`lib/domain/calculations/tracking_window.dart`, `backoffice/lib/tracking.ts` and
`public.tracking_since()` — and that is the point of
[`docs/contexto-diario.md`](./docs/contexto-diario.md).

The first run needs a `.env.local` — see
[`backoffice/README.md`](./backoffice/README.md), which also explains how the
access is granted and what to check when the list of patients comes up empty.

What protects the data is not that app: it enters with the publishable key and
the viewer's own session, and Postgres decides what comes back
(`supabase/migrations/20260803000100_care_access.sql`, verified by
`supabase/tests/care_access_test.sql` in CI).

## Legal

[`PRIVACY_POLICY.md`](./PRIVACY_POLICY.md) · [`TERMS_OF_SERVICE.md`](./TERMS_OF_SERVICE.md)
