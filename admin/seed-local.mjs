/**
 * Seeds the LOCAL EMULATOR with realistic-looking accounts so the panel has
 * something to show. Development convenience only — it refuses to run unless
 * FIRESTORE_EMULATOR_HOST is set, so it can never touch a real project.
 *
 * Document shapes mirror `lib/services/sync_mapper.dart` (`dailyLogToMap`) and
 * `SyncService._pushSettings`. Note it deliberately never writes `users/{uid}`
 * itself — the app doesn't either, and the panel has to work without it.
 *
 *   firebase emulators:exec --only firestore,auth --project demo-lunatrack \
 *     --config ./firebase.json 'node seed-local.mjs'
 */
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';

import { LUNA_DATABASE_ID } from './src/paths.js';
import { getAuth } from 'firebase-admin/auth';

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error('refusing to run: FIRESTORE_EMULATOR_HOST is not set.');
  process.exit(1);
}

const PROJECT_ID = 'demo-lunatrack';
const DATABASE_ID = process.env.LUNATRACK_DATABASE_ID ?? LUNA_DATABASE_ID;

const app = initializeApp({ projectId: PROJECT_ID });
const db = getFirestore(app, DATABASE_ID);
const auth = getAuth(app);

const DAY = 86_400_000;
const iso = (ms) => new Date(ms).toISOString().slice(0, 10);

/** A dailyLogs document shaped exactly like `dailyLogToMap` writes them. */
const dayDoc = ({ date, flow, symptoms = {}, mood = null, notes = null, bbt = null, opk = null, deviceId, updatedAt }) => ({
  date, flow, symptoms, mood, notes, bbt, opk,
  createdAt: updatedAt, updatedAt, deviceId,
  syncedAt: new Date(updatedAt),
});

const accounts = [
  {
    uid: 'u-ada', email: 'ada@example.com', days: 96, devices: ['pixel-8', 'tablet-a'],
    mode: 'conceive', tracking: ['flow', 'symptoms', 'bbt', 'weight'],
    // A fully answered signup baseline, so the records page has the block to
    // render. `u-bea` below exercises the free-text and retired-key paths, and
    // `u-cleo` leaves it unset so "never asked" is visible too.
    baseline: {
      sexFrequency: 'freq_weekly', soloFrequency: 'freq_rarely',
      libido: 'lbd_medium', history: ['shx_none'],
      soloWays: ['slfw_hands'], satisfactionTime: 'sat_5_15',
    },
    flavour: (i) => ({
      flow: i % 28 < 5 ? [4, 4, 3, 2, 1][i % 28] : 0,
      symptoms: i % 28 < 5
        ? { cramps: true, headache: i % 3 === 0, med_ibuprofen: true, pain: 6, weight: 61.2 }
        : (i % 9 === 0 ? { sex_protected: true, cm_eggwhite: true, energy: 4 } : { weight: 61.4 }),
      mood: ['calm', 'low', 'irritable', 'happy'][i % 4],
      notes: i % 14 === 0 ? 'Slept badly, back ache all afternoon.' : null,
      bbt: 36.4 + ((i % 28) > 14 ? 0.3 : 0) + (i % 5) * 0.02,
      opk: (i % 28) === 13 ? 'positive' : null,
    }),
  },
  {
    uid: 'u-bea', email: 'bea@example.com', days: 34, devices: ['moto-g'],
    mode: 'track', tracking: ['flow', 'symptoms'],
    baseline: {
      sexFrequency: 'freq_never', soloFrequency: 'freq_often',
      libido: 'lbd_high', history: ['shx_pain', 'vag_dryness'],
      // `slfw_private` was retired from the picker on 2026-09-18 and must still
      // read back as the deliberate refusal it was, not as an unknown key.
      soloWays: ['slfw_toy', 'slfw_private', 'slfw_other'],
      soloWayOther: 'her own words land here, verbatim',
      satisfactionTime: 'sat_under5',
    },
    flavour: (i) => ({
      flow: i % 30 < 4 ? [3, 3, 2, 1][i % 30] : 0,
      // `slf_`/`lbd_` are the DAY tags, deliberately seeded alongside Bea's
      // signup baseline above: the records page shows both, and they answer
      // different questions. The day tag records THAT a day involved
      // masturbation; the baseline records HOW. `slf_none` is a real answer
      // ("not today"), not an absence, which is why it is seeded too.
      symptoms: i % 6 === 0
        ? { bloating: true, skin_acne: true, water: 5, slf_masturbation: true, lbd_high: true }
        : (i % 5 === 0 ? { slf_none: true, lbd_low: true } : {}),
      mood: ['calm', 'anxious'][i % 2],
      notes: null, bbt: null, opk: null,
    }),
  },
  {
    // Pending deletion — inside the grace window. The panel must flag this.
    uid: 'u-cleo', email: 'cleo@example.com', days: 12, devices: ['pixel-6'],
    mode: 'track', tracking: ['flow'], pendingDeletion: true,
    flavour: (i) => ({
      flow: i < 4 ? 2 : 0, symptoms: {}, mood: null,
      notes: i === 2 ? 'Trying a new supplement this month.' : null, bbt: null, opk: null,
    }),
  },
  {
    // Signed up, never synced anything: no subcollections at all.
    uid: 'u-dot', email: 'dot@example.com', days: 0, devices: [], mode: null, tracking: null,
  },
];

const now = Date.now();

for (const a of accounts) {
  await auth.createUser({ uid: a.uid, email: a.email, password: 'passw0rd!' }).catch(() => {});

  for (let i = 0; i < a.days; i++) {
    const at = now - i * DAY;
    const date = iso(at);
    await db.doc(`users/${a.uid}/dailyLogs/${date}`).set(
      dayDoc({ date, deviceId: a.devices[0], updatedAt: at, ...a.flavour(i) }),
    );
  }

  if (a.mode) {
    await db.doc(`users/${a.uid}/settings/current`).set({
      mode: a.mode, cycleLength: 28, periodLength: 5, themeMode: 'system',
      language: 'en', genderNeutralLanguage: false, pregnancyStartDate: null,
      trackingCategories: a.tracking, weightUnit: 'kg',
      // A JSON STRING, exactly as `SyncService._pushSettings` writes the drift
      // column — not a map. Absent (not null) when the account never answered.
      ...(a.baseline ? { sexualHealthBaseline: JSON.stringify(a.baseline) } : {}),
      updatedAt: now - DAY, syncedAt: new Date(now - DAY),
    });
  }

  for (const d of a.devices) {
    await db.doc(`users/${a.uid}/devices/${d}`).set({
      lastPulledAt: new Date(now - 2 * DAY), updatedAt: now - 2 * DAY,
    });
  }

  // A deleted day leaves only a date marker — no health content survives.
  if (a.days > 20) {
    const gone = iso(now - 40 * DAY);
    await db.doc(`users/${a.uid}/deletions/${gone}`).set({
      date: gone, deletedAt: now - 39 * DAY, syncedAt: new Date(now - 39 * DAY),
    });
  }

  if (a.pendingDeletion) {
    await db.doc(`deletionRequests/${a.uid}`).set({
      uid: a.uid,
      requestedAt: new Date(now - 3 * DAY),
      purgeAfter: new Date(now + 27 * DAY),
    });
  }

  console.log(`seeded ${a.email.padEnd(18)} ${String(a.days).padStart(3)} days` +
    `${a.pendingDeletion ? '  (deletion pending)' : ''}${a.days === 0 ? '  (never synced)' : ''}`);
}

console.log('\nseed complete — 4 accounts, 142 day logs, 1 pending deletion');
