# Privacy Policy

_Last updated: 2026-07-30_

This document describes what Ceres ("the app") actually collects, stores,
and shares, based on how it is built today. It is a starting point, not legal
advice — see the note at the end before relying on it for a store listing or
a specific jurisdiction's requirements.

## Who this covers

Ceres is developed by [insert legal name / entity]. Contact for privacy
questions: [insert contact email].

## What we collect

**Account.** Email and password (handled entirely by our authentication
provider, Supabase Auth — we never see or store your password ourselves),
plus display name, sex, birth date, height, activity level, and unit/locale
preferences.

**Health and nutrition data you log.** Meals and their items, activities,
weight, body measurements, water, sleep, and goals. This is the core content
of the app.

**Meal photos.** If you take a photo of a meal, it's uploaded to a private
storage bucket tied to your account and analyzed by Google's Gemini API to
estimate what's on the plate — you always review and confirm the result
before it's saved. Only the image itself is sent for analysis, with no other
identifying information attached.

**Local, on-device copy.** The app keeps a local copy of your data on your
phone so it works without a connection. This copy is not encrypted beyond
whatever your device's own storage protections provide.

## How your data is used

- To run the app: calculating your daily totals, trends, and history.
- To estimate meal contents from a photo or a text description (Gemini) and
  to search generic foods (USDA FoodData Central) or barcoded products (Open
  Food Facts) — for these lookups, only your search text or the photo itself
  is sent, never your account information.
- To back up your data automatically so you don't lose it if you lose your
  phone, and to sync it if you use the app on more than one device.

We do not sell your data, and we do not use it for advertising — the app has
no ad or tracking SDKs.

## Sharing with other people ("Pals")

Ceres lets you link your account with other people ("pals") by a short
code, so you can see each other's day. This is entirely opt-in and under your
control:

- What an accepted pal **always** sees: the meals you logged that day and
  whether you were active.
- What you can additionally choose to share, each off by default until you
  turn it on: your meal photos, how much water you drank, how you slept, and
  a detailed breakdown of each activity (instead of just the totals).
- What is **never** shared with a pal, regardless of any setting: your
  weight and your body measurements.
- You can remove a pal at any time, which immediately stops any further
  sharing between you.

## Third parties

| Who | What they receive | Why |
| --- | --- | --- |
| Supabase | Your account and app data | Hosting, authentication, and storage |
| Google Gemini | A meal photo, a text description, or — if you ask for meal suggestions — how many calories and how much protein you have left for the day | Estimating meal contents; suggesting meals that fit |
| USDA FoodData Central | A search term | Looking up generic foods |
| Open Food Facts | A search term or barcode | Looking up branded products |
| GitHub | Nothing you typed, but the request itself: your IP address and app version, each time the app opens | Checking whether a newer release exists (the app is distributed outside Play Store) |

Nothing sent to Gemini, USDA, Open Food Facts, or GitHub carries your name,
email, or account id.

## Your controls

- **Export or delete your local data** at any time from Settings → Privacy.
- **Delete your account** from the same screen. This removes, immediately and
  permanently: your profile, meals, activities, weights, measurements, sleep,
  water, pal links, every photo in our storage buckets, your cloud backups,
  and the account itself. There is no grace period and nothing is recoverable
  afterwards, so export your data first if you want to keep it.
- **Turn off any Pals sharing category** at any time from Profile → "What my
  pals see" — the change applies going forward, not retroactively to what a
  pal already saw.

## Changes to this policy

If how the app handles data changes in a way that matters, this document
gets updated alongside the change, not after.

---

**Note on this document.** It was drafted directly from the app's source
code to describe actual behavior, not aspirational or boilerplate language.
It has not been reviewed by a lawyer. Before publishing this for real users —
especially for app store submission, or if users outside Argentina are
expected — have it reviewed against the data protection law that applies to
you (e.g. Argentina's Ley 25.326, GDPR if you have EU users, CCPA if you have
California users) and against Google Play's own data safety requirements if
this ever gets distributed there.
