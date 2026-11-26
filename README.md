# Ceres

Android app for tracking food, activity, weight, water and sleep, with a web
panel for nutritionists to follow their patients.

## Features

- **Meals** — food catalog (Argentine foods, USDA, Open Food Facts by barcode),
  plain-text or voice descriptions, or a photo. AI estimates the items and you
  confirm before anything is saved.
- **Activity** — MET-based calorie estimates with an adjustable exercise credit.
- **Body** — weight, body measurements, water and sleep, editable for any date.
- **Progress** — trends, day-by-day history and a PDF report.
- **Pals** — share your day with people you choose, category by category.
- **Professional panel** ([`backoffice/`](./backoffice/)) — read-only access to
  what the patient grants, revocable at any time.

## Stack

Flutter (Android) · Supabase (Postgres with row-level security, Auth, Storage,
Edge Functions) · Gemini · Next.js for the panel.

## Running it

```bash
flutter pub get
flutter run    # local mode: no login, nothing leaves the device
flutter test
```

Local mode needs no credentials. To run against your own Supabase project, copy
`env/local.json.example` to `env/local.json`, fill it in and add
`--dart-define-from-file=env/local.json`. The panel has its own setup in
[`backoffice/README.md`](./backoffice/README.md).

## Legal

[`PRIVACY_POLICY.md`](./PRIVACY_POLICY.md) · [`TERMS_OF_SERVICE.md`](./TERMS_OF_SERVICE.md)
