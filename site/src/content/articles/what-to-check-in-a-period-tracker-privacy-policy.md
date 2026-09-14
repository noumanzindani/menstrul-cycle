---
title: What to Check in a Period Tracker's Privacy Policy
description: A concrete checklist for reading any period tracker's privacy policy, applied honestly to LunarFlow itself — including the places it falls short.
author: LunarFlow
reviewedBy: Not medically reviewed
datePublished: 2026-09-12
dateModified: 2026-09-13
sources:
  - title: ICO — Your right to get your data deleted
    url: https://ico.org.uk/for-the-public/your-right-to-get-your-data-deleted/
  - title: NHS — Periods
    url: https://www.nhs.uk/conditions/periods/
---

Period-tracking data is not an ordinary data category. A log of dates and
symptoms can reveal whether someone might be pregnant, trying to conceive,
perimenopausal, or dealing with a health condition, and in some places and
situations that information carries real consequences if it ends up somewhere
the person logging it did not expect. A privacy policy is the one document that
is supposed to tell you exactly where that information goes — but most people
never read one, and the ones that do read one often do not know what to look
for. This article is a checklist you can run against any tracker's policy
before installing it. Then, because a checklist that only ever gets pointed at
competitors is not worth trusting, we run it against LunarFlow's own policy —
including the parts where the answer is not the one we would prefer to give.

## The checklist

Read a tracker's privacy policy — or the plain-language summary at the top of a
good one — and look for a direct answer to each of these. A policy that avoids
answering one of them plainly, in favor of vague reassurance, is telling you
something by the avoidance itself.

**1. Does using the app require creating an account, and what does that account
need from you?** An account tied to an email address links everything logged
under it to an identity the company holds. Check whether an account is
mandatory to use the core tracking features, or whether there is a genuine way
to log your cycle without providing any identifying detail at all — and if
there is, check whether that path is a fully supported way to use the app, or
a fallback that only appears in specific circumstances like a server outage.
Those are very different guarantees, and a policy that blurs the two is worth
being suspicious of.

**2. Where is your logged data stored, and is it stored in a form the operator
of the service can actually read?** "Stored securely" is not an answer to this
question — access controls, transport encryption, and encryption that keeps
the operator itself out are three different levels of protection, and a policy
should be specific about which one it means for your health data. If a policy
says your data is protected but never says from whom, ask specifically whether
the company could, in principle, open your logs and read them.

**3. Are photos or videos handled differently from text logs?** Media is often
treated with a separate, and sometimes weaker, set of protections than symptom
and date entries. Check whether images ever leave your device at all, whether
they are stored in a form readable by the operator, and whether that answer
changes if you use an optional feature like an AI-based description tool —
uploading a photo to enable a feature is a different disclosure than a photo
being uploaded automatically just because you took one in the app.

**4. Is your data used for advertising, and what reaches the ad network if
ads are shown?** A free app supported by ads should say plainly whether ad
requests are personalized to you, and whether any health or cycle data is
included in what is sent to an ad partner. It should also say whether ads
appear on the screens where you actually log symptoms, moods, or notes, since
that is the context where an ad appearing at all feels most invasive,
independent of what data technically moves.

**5. If there is a paid tier, what does it change?** Some apps use a paid tier
to remove ads; a smaller number use it to unlock additional data collection or
a different privacy posture entirely. The policy should make clear whether
paying changes what is collected, or only changes what you see.

**6. Can you delete your account, and does deletion actually erase the server
copy — on what timeline?** In the UK and EU, the right to erasure is a real
legal right, not a courtesy; the ICO's guidance on the right to get your data
deleted sets out what a service is expected to do with a deletion request and
on what basis it can refuse one. A trustworthy policy states plainly what
happens when you ask to delete your account: whether deletion is immediate or
subject to a grace period, whether backups or logs are exempt, and — critically
— whether the deletion mechanism has actually been built and is live, rather
than merely described.

**7. Is on-device data encrypted at rest, and does that protection extend to
everything the app stores locally, or only part of it?** An app might encrypt
its main database with a key held in the device's secure hardware store, which
is a meaningful protection against someone who gets hold of the device itself
— but a separate cache used by a sync or networking component can easily fall
outside that protection if it was not deliberately included. A policy that
claims "encrypted at rest" without saying which files that covers is making a
narrower promise than it sounds like.

**8. Does the policy say how long your data is kept, and is there any limit
beyond "until you delete it"?** Retention is easy to leave out entirely,
because silence on it looks the same as a considered decision. Look for a
stated maximum — data automatically removed after a period of inactivity, or a
hard ceiling regardless of how long the account stays open — rather than a
retention period that is really just "for as long as you keep the account,"
which is not a limit at all. The longer sensitive data sits somewhere, in more
places, across more years, the more there is to expose if the storage is ever
breached, subpoenaed, or simply mishandled, and a policy that never addresses
retention is leaving that question for you to assume an answer to.

**9. Does the policy say how the operator handles law-enforcement, subpoena,
or other government requests for your data — what it would disclose, whether
it pushes back on overbroad requests, and whether it publishes a transparency
report or notifies users?** This is not a hypothetical concern for
period-tracking data specifically: cycle and pregnancy-related records have
been sought as evidence in legal proceedings elsewhere, which is exactly why
this question belongs on the checklist rather than being treated as generic
boilerplate. A policy that states its process for legal requests, commits to
notifying users where the law allows it, or publishes a transparency report is
giving you a real answer. A policy that says nothing on the subject has not
addressed the question, and a reader is entitled to notice the silence rather
than assume the best.

Answering all nine honestly takes more than a sentence, which is exactly why
so many privacy policies use broad reassurance instead of specifics. Below is
LunarFlow's own answer to each one.

## Applying it to LunarFlow

**1. Account.** LunarFlow requires creating an account with an email address
and a password before you can use the tracker; this is not optional for normal
use. There is one narrow exception: if the app cannot reach its cloud service
at all when it starts, the sign-in screen offers to continue with your data
kept only on the device for that session. That path exists for an outage, not
as an alternative way to choose to use the app — it disappears again the next
time the cloud service is reachable, and anything logged during it is offered
up to your account, with your confirmation, the next time you sign in.

**2. Storage and readability.** Once you are signed in, your daily logs —
flow, symptoms, mood, notes, and the other tags you record — sync to
LunarFlow's cloud database in a form that is not encrypted against the
operator. Access to it is restricted by account-scoped rules rather than by
encryption that would keep the company itself out, which means the operator of
the service is technically able to read it, the same way most cloud apps that
sync a mutable, searchable record can be read by the service that hosts it.
This is the opposite of the strongest answer to question two above, and it is
worth saying plainly rather than describing around: the protection here is
"only people with the right access can reach it," not "the provider cannot
read it even if they wanted to."

**3. Photos and videos.** LunarFlow's photo and video timeline is a cloud
feature with no option to keep media on the device only — an item exists in
the app once it has finished uploading. Those files are stored unencrypted and
are, like the logs above, viewable by the operator; they are protected by
account access, not by encryption. This is true independent of the separate,
opt-in photo-description feature, which is a further disclosure on top (a
photo you choose to describe is sent to an outside recognition service) rather
than the reason media reaches the cloud in the first place.

**4. Advertising.** LunarFlow shows ads through Google AdMob on the free
tier. Ad requests are non-personalized, and no health data, cycle data, or
personal identifier is included in what is sent to the ad network. Ads are not
shown on the screens where symptoms, moods, or notes are actually logged, or
on the insights screens — the parts of the app where an ad appearing would sit
right next to the most sensitive part of what you are doing.

**5. Paid tier.** LunarFlow has a one-time paid upgrade that removes ads. It
does not change what data is collected or synced; the underlying account and
sync behavior is identical on the free and paid tiers.

**6. Deletion.** Account deletion is a real request with a grace period, not
an instant erasure: your device is wiped immediately, and the account and its
server-side data are scheduled for removal after a fixed number of days,
during which the request can be cancelled. That much matches good practice.
Where LunarFlow currently falls short is the automated step at the end of that
window — the scheduled removal job that is supposed to carry it out has not
been switched on yet, which means a request today stops sync and wipes the
device, but does not yet guarantee the scheduled server-side deletion happens
without further action. A policy that said otherwise right now would not be
telling the truth, so ours does not.

**7. On-device encryption.** LunarFlow's local database is encrypted at rest,
using a key generated on the device and held in the operating system's secure
keystore rather than anywhere the app itself can export it. That protection
does not extend to everything on the device, though: the sync component keeps
its own working copy of recently synced entries for the mechanics of syncing,
and that working copy sits outside the encrypted database. It is erased by the
same in-app controls that erase everything else, but while it exists it is not
covered by the same guarantee as the main database.

**8. Retention.** LunarFlow's policy states that your data is kept for as
long as your account exists, with no other retention limit. The only
exception is the dates-only deletion markers used to propagate erasures
between devices, which are pruned after 180 days — everything else, including
every daily log and every uploaded photo, has no retention ceiling beyond
"the account is still open." That is the honest answer, not a comfortable
one: there is no independent limit here.

**9. Legal and government requests.** LunarFlow's policy does not address
this at all. It contains no section on law enforcement, subpoenas, court
orders, or other government requests, no statement of what would or would not
be disclosed, and no mention of a transparency report or a commitment to
notify users where the law permits it. That is a real gap in the document, not
a question this article can answer on the policy's behalf — the honest grade
here is that the policy is silent on this.

## The honest summary

Run against its own checklist, LunarFlow requires an account for normal use,
stores your synced logs and media in a form its operator can technically
read, shows non-personalized ads that never touch the logging or insights
screens, offers a paid ad-removal tier that does not change data handling, has
a deletion process whose final automated step is not live yet, encrypts its
on-device database with a device-held key that does not cover the sync
component's working copy, keeps your data for as long as the account exists
with no further retention limit, and says nothing anywhere about how it would
handle a law-enforcement or government request for your data. Some of that is
a solid answer. Several of those, including the last two, are not the answer a
period tracker's marketing page would prefer to give, and we would rather
publish the plain version than a flattering one — the same standard this
checklist asks you to hold every other tracker to, including the ones that
would rather you did not ask.

## Where to go from here

If cycle-length variation or irregular timing is part of what is prompting you
to think harder about which tracker to trust with this data in the first
place, the [cycle-length calculator](/tools/cycle-length-calculator) on this
site is a reasonable next stop — it runs entirely in your own browser and does
not ask you to sign up for anything to use it. For the mechanics behind the
dates any tracker shows you, including the assumptions baked into an ovulation
estimate, see [how period predictions actually work](/articles/how-period-predictions-work).
And for LunarFlow's full policy in the exact legal language rather than this
summary, along with everything [this app tracks](/features), see the
[privacy policy](/privacy-policy) and the plain-language [data page](/privacy).
