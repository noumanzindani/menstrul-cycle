# Play Store listing assets

Everything Google Play asks for at submission, except the screenshots — see
"Screenshots are deliberately missing" below, which is the one item that needs a
decision from you rather than more work from me.

`test/store_copy_test.dart` guards this directory. It enforces Play's length
limits and re-applies the repo's fertility and privacy rulings to copy that
lives outside `lib/`, where none of the existing `lib/`-scanning guards reach.

## What is here

| File | Play field | Spec | Status |
|---|---|---|---|
| `play/icon-512.png` | App icon | 512x512, 32-bit PNG | ✅ 512x512 RGBA |
| `play/feature-graphic-1024x500.png` | Feature graphic | 1024x500, no alpha | ✅ 1024x500 RGB |
| `play/short-description.txt` | Short description | ≤ 80 chars | ✅ 74 |
| `play/full-description.txt` | Full description | ≤ 4000 chars | ✅ 2290 |
| — | Phone screenshots | 2–8, 16:9 or 9:16 | ❌ see below |

The icon is the app's own launcher art, so the listing, the launcher and the
adaptive icon background all resolve to the same `#F489AF`.

## Screenshots are deliberately missing

I captured nine real screens on the device during verification and did **not**
put any of them here. They contain the owner's actual health data:

- Settings shows an **email address, date of birth, height, weight and age at
  first period**
- Today, Calendar and Forecast show a **real cycle** — logged period dates, a
  predicted next period, a fertile window

Publishing those to a Play listing publishes one person's menstrual and
identity data to the open internet, permanently and un-retractably. Store
screenshots need demo data, not a real account.

**To finish this, one of:**

1. **A throwaway account with seeded data** — sign up as e.g.
   `demo@…`, run onboarding with invented answers, log a plausible cycle, then
   capture. Creates one real Firebase Auth user in `teddy-2-20649`; delete it
   afterwards.
2. **A second Android user profile** (`adb shell pm create-user`) so the real
   install is untouched, then as above.
3. **An emulator** with a fresh install.

All three still need an account, because `AppGate` walls the app behind sign-in
and the local-only hatch is gated on `Firebase.initializeApp()` actually
failing — it is not a switch you can flip for a screenshot session.

Suggested set (5), in the order Play displays them:
Today · Calendar · Day log (chip grid) · Insights · Doctor PDF summary.

## Copy decisions worth knowing

**"Private" is not the headline, on purpose.** Accounts are required and daily
logs sync to Firestore in plaintext where the operator can read them. The
listing says so in as many words. A tracker that led on privacy while doing
that would be making a claim the code does not keep — and it is the claim Play
and the press check hardest on this category.

What the copy leads on instead: calm, un-gamified, free, honest about
estimates, doctor-ready.

**The fertility rulings apply here too.** No "safe day" — banned even negated,
because a skimming reader takes away the two words in a fertility context. No
synthesised percentage. The non-contraception disclaimer is mandatory copy, and
the test asserts its presence rather than trusting review.

**"Encrypted at rest" is scoped to the device.** It covers the drift database
only — never the synced copy, never uploaded media in Cloud Storage.

## Before you submit — still open

These are listing-adjacent and not solved by anything in this directory. The
full list with rationale is `README.md` → "Before publishing".

- **Privacy policy URL** — `PRIVACY_POLICY.md` must be hosted publicly and
  entered in Play Console → App content.
- **Account-deletion URL** — `docs/account-deletion.md` likewise, in the
  data-deletion field. **The docs currently contradict each other on whether
  the purge job is live:** `docs/HANDOFF.md` says it was deployed 2026-09-14,
  `README.md` still lists it as an open blocker. Settle that before filling in
  this field — the answer changes what you are allowed to promise.
- **Data Safety form** — health data is collected AND transmitted, tied to user
  identity. Declare sexual-activity and pregnancy data. Do not tick
  end-to-end encryption.
- Real upload keystore (release is debug-signed today).
- Real AdMob app + unit IDs (Google test IDs are still wired).
- Real Play product id for the Premium purchase.
- Gemini API key still ships inside the APK.
