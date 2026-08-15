# Deleting your LunaTrack account

This page explains how to delete your LunaTrack account and the data stored with
it, both from inside the app and without it.

> ⚠️ Before publishing: host this page at a public URL, put that URL in the
> Google Play listing's account-deletion field, and replace the placeholder
> contact address below. Also read "Current status" at the bottom — the
> automated erasure job is not in operation yet.

## In the app

**Settings → Account → Request account deletion.**

This is a request with a 30-day grace period, not an instant erasure. When you
confirm:

1. **Everything on that device is erased immediately** — every period, symptom,
   medication, reminder and setting, plus the app's local copy of anything it
   had synced. You are signed out.
2. **Your account and the copy of your logs on our servers are kept for 30
   days**, then permanently deleted.
3. **Cloud sync is switched off for the account** for the whole 30 days. Nothing
   is uploaded or downloaded for it, from any device.

### Changing your mind

Sign in again within the 30 days. The app shows the pending request on launch,
with the deletion date and a **Cancel deletion** button; the same button is in
**Settings → Account**. Cancelling stops the deletion, restores the account, and
syncs your logs back to the device.

If you do nothing, the request stands.

Note that other devices already signed into the account are **not** wiped by the
request — only the device you made it on. They keep their local copy and can
carry on working offline, and they will show the same pending notice. Use
**Settings → Delete all my data** on each of those devices if you want them
erased too.

## Without the app

Email **your-email@example.com** _(replace before publishing)_ from the address
you signed up with, with the subject **"Delete my LunaTrack account"**. The
account is queued for deletion on the same 30-day terms as the in-app request,
and we will confirm by reply to that address.

## What is deleted

Everything stored under your account:

- All daily logs — flow, symptoms, mood, notes, sexual activity, medication
  marks, weight and other numeric metrics, basal body temperature and ovulation
  test results.
- Your synced preference settings, including pregnancy start date.
- The per-device sync bookkeeping and the deletion markers (dates only).
- The account itself, including the email address it was created with.

## What is not covered

- **Data held only on a device** is removed by erasing that device's data in the
  app (Settings → Delete all my data) or by uninstalling the app.
- **Files you exported yourself** — doctor-summary PDFs and `.lunabak` backup
  files you shared or saved — are yours and are outside our reach.
- **Your Google Play purchase history** for Premium is held by Google, not by
  us.
- **A photo you sent for description.** If you turned on Settings → Describe
  photos and tapped Describe on a photo, that photo was sent to Google at that
  moment. Deleting your LunaTrack account does not reach it — it is outside our
  systems and outside our control. LunaTrack keeps no description and nothing
  derived from it, so there is nothing on our side left to erase.

## Current status

The app records deletion requests, stops syncing the account, and erases the
requesting device today. The scheduled job that carries out the permanent
server-side erasure after 30 days **has not been built yet**, so no deletion
request is completed automatically at present.

Until that job ships, requests must be honoured manually, and neither this page
nor the app should be published — Google Play requires a working in-app account
deletion path. See the pre-publication blockers in `README.md`.
