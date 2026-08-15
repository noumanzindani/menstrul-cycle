# LunaTrack Privacy Policy

_Last updated: 7 August 2026_

LunaTrack ("the app", "we") is a menstrual and cycle tracking app. This policy
explains what data the app handles and how. **Short version: LunaTrack uses an
account, and the health data you log is uploaded to our cloud database so it can
sync between your devices. It is stored in a readable form and is not sold or
shared with advertisers. If you turn on photo descriptions, a photo you tap
Describe on is sent to Google; that is off unless you turn it on.**

> ⚠️ Before publishing, all of the following must be true:
>
> 1. Host this page at a public URL (e.g. GitHub Pages) and enter that URL in
>    Google Play Console → App content → Privacy policy.
> 2. Replace the contact email below with a real address, and use the same
>    address in `docs/account-deletion.md` and in the store listing.
> 3. Ship the scheduled purge job described under "Deleting your account".
>    **Until it exists, the deletion promise in this document is not kept.** See
>    the pre-publication blockers in `README.md`.

## Do you need an account?

Yes. LunaTrack asks you to create an account with an **email address and
password** (Firebase Authentication) before you use the tracker.

There is one exception. If the app cannot reach our cloud service at all when it
starts, the sign-in screen offers **"Continue without syncing"**. That session
has no account, uploads nothing, and keeps a banner on screen saying cloud sync
is unavailable. Anything you log that way stays on the device, and the next time
you sign in the app asks — before uploading anything — whether you want to add
that existing data to your account.

## What data the app stores on your device

Everything you enter — periods, flow, symptoms, moods, **sexual activity**,
medication marks, notes, weight, basal body temperature, ovulation test results,
reminders and settings — is written first to a database on your device. The app
works fully offline; the device copy is the source of truth and the cloud copy
is a mirror of it.

- The app's own database is **encrypted at rest** on your device with a 256-bit
  key that is generated on the device, stored in the operating system's
  keystore, and never leaves it. We never see this key.
- Note that the cloud-sync component keeps its own working copy of recently
  synced documents on the device, and that copy is **not** covered by the above
  encryption. Both copies are erased by the in-app erase and deletion controls
  described below.

## What is uploaded to our servers

When you are signed in, the following is stored on Google Cloud infrastructure
(Firebase Firestore), under a folder identified by your account (`users/{your
account id}`):

- **Daily logs** — the date, flow, the whole symptom/tag record for that day
  (which includes symptoms, mood, **sexual activity**, medication marks,
  cervical mucus, lifestyle and habit tags, and numeric metrics such as pain,
  sleep, stress and **weight**), free-text **notes** (the same text the in-app
  diary shows), basal body temperature, ovulation test result, and the times the
  entry was created and last changed.
- **Preference settings** — tracking mode, your default cycle and period
  lengths, theme, language, gender-neutral-language choice, **pregnancy start
  date**, which tracking categories you enabled, and your weight unit.
- **Photos and videos you add** — the media timeline is a cloud feature. There
  is no on-device-only option for it: a photo or video exists in LunaTrack only
  once it has been uploaded to your account, which is what lets it appear on
  your other devices. Alongside the file itself we store when it was taken, how
  large it is, its dimensions or length, and a small thumbnail.
- **Bookkeeping** — a random per-installation device identifier stamped on each
  synced entry, a small per-device record of how far that device has synced, and
  markers recording the dates of days you deleted so the deletion reaches your
  other devices. Those markers are dates only; they contain no health content.

This data is stored **in plaintext** — it is not end-to-end encrypted, and it is
readable by the operator of the service. **It is not sold, and it is not shared
with advertisers.**

Some of what you can log — sexual activity, pregnancy state and health symptoms
— is especially sensitive. It is uploaded on the same terms as everything else
above, and it is still excluded by default from the doctor-summary PDF.

### Photos and videos, specifically

This deserves its own paragraph, because it is the part people most often assume
works differently than it does.

- Your photos and videos are stored **unencrypted**. They are protected by your
  account and by access rules, not by encryption. **The operator of the service
  can view them.** Do not upload anything you would not be willing to have seen.
- They are **not** included in the doctor-summary PDF, **not** shown on the
  home-screen widget, and **not** included in the encrypted backup file you can
  export — a backup restored into a different account could not read them.
- Full-size media you have viewed is kept in a temporary cache on your device so
  it does not have to be downloaded twice. That cache is inside the app's
  private storage and is erased by "Delete all my data", by requesting account
  deletion, and by signing out. Thumbnails are held inside the encrypted
  database.
- Photos are stripped of location data by the Android photo picker before
  LunaTrack ever receives them; the app never asks for the permission that would
  reveal it.
- **They are covered by the same gap as everything else in the cloud**: see
  "Deleting your account" below. Until the purge job is deployed, requesting
  deletion does not automatically erase your uploaded media from the server.

### Describing a photo (off unless you turn it on)

LunaTrack can describe what is in one of your photos. This feature is **off by
default**, and turning it on is a separate choice from cloud sync.

- It is **off until you turn it on**, per account, on each device. You are asked
  once, the first time you tap **Describe** on a photo, and you can turn it off
  again at any time in Settings → Describe photos.
- When you tap **Describe**, that one photo is **sent to Google**, an automatic
  image-recognition service that is not part of LunaTrack and not part of your
  account. It happens only for the photo you tapped, only when you tap, and
  never on its own or in the background.
- You can then **ask follow-up questions** about that photo. Each question you
  send **sends the photo again**, along with the questions and answers so far,
  because the service keeps nothing between messages. Nothing is sent while you
  are typing — only when you send a message.
- **Google is a separate company with its own terms and its own handling of what
  it receives.** LunaTrack cannot speak for what happens to a photo after it is
  sent, and does not claim to.
- LunaTrack **does not store the description or the conversation**. Both are
  shown to you and discarded when you close the photo — closing it and opening
  it again starts over, with nothing carried across. Nothing derived from your
  photo is written to the database, to the cloud, to the doctor PDF, or to the
  backup file.
- A description is **not a medical opinion**. The feature describes what is
  visible in a picture. It cannot tell you what something is, how serious it is,
  or what to do about it, and it is instructed to refuse if asked.
- **Once a photo has been sent, it has left LunaTrack.** Turning the feature off,
  deleting the photo, or deleting your LunaTrack account does not reach a copy
  held by Google.
- The number of **messages** is limited per day, and the number of questions
  about any one photo is limited too. These are cost limits, not privacy
  controls.

### What is never uploaded

- **Reminders and notification schedules** stay on the device.
- **Your medication list** (names, doses, schedules) stays on the device; only
  the per-day "took it" marks travel, as part of the daily log.
- **Your app-lock PIN**, whether app lock is on, and whether you have completed
  onboarding are per-device and stay on the device.
- **Premium** is a Google Play purchase and is not synced by us; it is tied to
  the Play account that bought it, not to your LunaTrack account.

## Advertising

The free version of LunaTrack shows ads via **Google AdMob**.

- We request **non-personalized ads only**. We do **not** send your health data,
  cycle data, or any personal identifiers to the ad network. **Ad partners never
  receive anything you log.**
- On first launch we present a consent choice (Google's User Messaging Platform)
  where required by law (e.g. GDPR regions).
- Ads are shown only on the Home, Calendar, Forecast and Settings screens. We do
  **not** show ads on the symptom-logging, diary, or health-insights screens.
- Purchasing **Premium** removes all ads.

AdMob may process limited technical data (such as a device advertising
identifier and coarse, non-personalized signals) to serve and measure ads. See
Google's policy: https://policies.google.com/technologies/ads

## Purchases

Premium is a one-time in-app purchase processed by the Google Play Store. We do
not receive or store your payment details; the store handles the transaction.

## Permissions

- **Internet** — to sign in and to sync your logs to your account.
- **Notifications** — to deliver the reminders you enable. Optional.
- **Biometric/device credential** — only if you enable the in-app lock, to
  unlock the app. Handled by your device; we never receive biometric data.

## Data you choose to export

- **Doctor summary PDF** — generated on your device and handed to the system
  share sheet. Where that file goes next is controlled entirely by you.
- **Backup file** — the in-app backup writes a `.lunabak` file that is encrypted
  with a passphrase you choose, and hands it to the share sheet. We never see
  the file or the passphrase; if you lose the passphrase the file cannot be
  recovered.

## Erasing the data on one device

**Settings → Delete all my data** erases every period, symptom, medication,
reminder and setting on that device, and turns cloud sync off for your account
on that device so nothing is downloaded back.

**It does not delete the copy on our servers.** Your account keeps your logs,
and you can turn sync back on later under Settings → Account. To remove the
server copy, use account deletion below.

Uninstalling the app removes the device copy only, on the same terms.

## Deleting your account

**Settings → Account → Request account deletion.**

This is a request with a grace period, not an instant erasure:

1. Everything on that device is erased immediately.
2. Your account and the copy of your logs on our servers are **kept for 30
   days** and are scheduled for permanent deletion after that.
3. Cloud sync is switched off for the account while the request stands — nothing
   further is uploaded or downloaded for it, on any device.
4. **You can cancel** at any point in those 30 days by signing in again: the app
   shows the pending request on launch and in Settings → Account, with a "Cancel
   deletion" button. Cancelling restores the account and syncs your logs back.

You can also request deletion without the app — see
[docs/account-deletion.md](docs/account-deletion.md).

> ⚠️ **Current status — must be resolved before publishing.** The scheduled job
> that carries out step 2 has not been built yet. Today the app records the
> request, stops syncing the account and erases the device, but the server copy
> is **not** automatically erased when the 30 days elapse. Do not publish this
> policy, or the app, until that job is in operation. This notice is here so the
> document never claims a deletion that does not happen.

## Retention

Your data is kept for as long as your account exists. There is no other
retention limit. Deletion markers (dates only, see above) are pruned after 180
days.

## Children

LunaTrack is intended for people who menstruate, which can include teenagers. We
request **non-personalized** ads only, and no health data is ever sent to
advertisers. We do collect an email address in order to run accounts, and health
data you log is stored against that account, so please do not create an account
for someone else.

## Medical disclaimer

LunaTrack provides estimates and general wellness information. It is **not a
contraceptive method**, and it does **not** provide medical diagnosis or advice.
Always consult a qualified clinician for medical concerns.

## Changes to this policy

If this policy changes, we will update the date at the top and publish the new
version at the same URL.

## Contact

Questions about this policy: **your-email@example.com** _(replace before publishing)_
