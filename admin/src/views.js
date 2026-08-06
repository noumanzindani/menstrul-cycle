// Server-rendered HTML. The browser receives rendered data and nothing else:
// no Firebase credential, no Admin SDK, no client SDK, no raw Firestore handle,
// no API token. There is no JavaScript on these pages at all, which is also why
// the CSP in `app.js` can forbid script outright.

const ESCAPES = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
};

/** Escapes for HTML text and attribute contexts. */
export const esc = (value) =>
  value === null || value === undefined
    ? ''
    : String(value).replace(/[&<>"']/g, (char) => ESCAPES[char]);

const iso = (date) => (date instanceof Date ? date.toISOString() : '');
const day = (date) => (date instanceof Date ? date.toISOString().slice(0, 10) : '—');
const stamp = (date) =>
  date instanceof Date ? `${date.toISOString().slice(0, 16).replace('T', ' ')}Z` : '—';

/** A `count()` result, which is either a number or a reported failure. */
const metric = (result) => {
  if (result === null || result === undefined) return '—';
  if (typeof result === 'number') return String(result);
  if (result.error !== undefined) {
    return `<span class="err" title="${esc(result.error)}">unavailable</span>`;
  }
  return String(result.count);
};

const CSS = `
:root{color-scheme:light dark;--fg:#16141a;--bg:#fbfafc;--mut:#6b6675;--line:#e2dfe8;--warn:#8a2f2f;--warnbg:#fdeeee}
@media (prefers-color-scheme:dark){:root{--fg:#eceaf0;--bg:#141318;--mut:#a19bad;--line:#2e2b36;--warn:#ffb4b4;--warnbg:#3a1f1f}}
*{box-sizing:border-box}
body{margin:0;font:15px/1.5 ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,sans-serif;color:var(--fg);background:var(--bg)}
main{max-width:960px;margin:0 auto;padding:24px 20px 72px}
h1{font-size:20px;margin:0 0 4px}h2{font-size:15px;margin:28px 0 8px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut)}
a{color:inherit}
nav{border-bottom:1px solid var(--line);padding:12px 20px;display:flex;gap:16px;align-items:baseline;flex-wrap:wrap}
nav b{font-weight:600}
.who{margin-left:auto;color:var(--mut);font-size:13px}
table{border-collapse:collapse;width:100%;font-size:14px}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid var(--line);vertical-align:top}
th{color:var(--mut);font-weight:600;font-size:12px;text-transform:uppercase;letter-spacing:.04em}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:10px}
.card{border:1px solid var(--line);border-radius:8px;padding:12px 14px}
.card .n{font-size:24px;font-weight:600}
.card .k{color:var(--mut);font-size:12px}
.mut,.note{color:var(--mut);font-size:13px}
.err{color:var(--warn)}
.flag{display:inline-block;padding:1px 7px;border-radius:99px;font-size:12px;background:var(--warnbg);color:var(--warn);font-weight:600}
.banner{border:1px solid var(--warn);background:var(--warnbg);color:var(--warn);border-radius:8px;padding:12px 14px;margin:14px 0}
form{border:1px solid var(--line);border-radius:8px;padding:14px;margin:14px 0}
label{display:block;font-size:13px;color:var(--mut);margin-bottom:4px}
input[type=text],textarea{width:100%;padding:8px;border:1px solid var(--line);border-radius:6px;background:transparent;color:inherit;font:inherit}
button{margin-top:10px;padding:8px 14px;border-radius:6px;border:1px solid var(--line);background:transparent;color:inherit;font:inherit;cursor:pointer}
.day{border:1px solid var(--line);border-radius:8px;padding:12px 14px;margin:10px 0}
.day h3{margin:0 0 6px;font-size:15px}
.day dl{display:grid;grid-template-columns:170px 1fr;gap:2px 12px;margin:0;font-size:14px}
.day dt{color:var(--mut)}
.day dd{margin:0}
.overflow{overflow-x:auto}
footer{margin-top:40px;border-top:1px solid var(--line);padding-top:12px}
`;

export function page({ title, actor, body }) {
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow">
<title>${esc(title)} — LunaTrack operator panel</title>
<style>${CSS}</style></head>
<body>
<nav><b>LunaTrack</b> <a href="/">Dashboard</a> <a href="/users">Users</a>
<span class="who">${esc(actor ?? '')}</span></nav>
<main>${body}
<footer class="note">Read-only. Every view of a user's health records is written
to an append-only audit log before the records are shown.</footer>
</main></body></html>`;
}

// --- dashboard ------------------------------------------------------------

const card = (k, n) => `<div class="card"><div class="n">${n}</div><div class="k">${esc(k)}</div></div>`;

export function dashboardView(data) {
  const a = data.accounts;
  const f = data.firestore;
  return `<h1>Dashboard</h1>
<p class="mut">Generated ${esc(stamp(data.generatedAt))}. Account figures come from
Firebase Auth (no Firestore reads, no health records touched); Firestore figures are
<code>count()</code> aggregations, never document sweeps.</p>
${a.truncated ? '<div class="banner">Auth roster sweep was truncated at the configured maximum — account totals are a lower bound.</div>' : ''}
<h2>Accounts (Firebase Auth)</h2>
<div class="grid">
${card('total accounts', a.total)}
${card('new — last 24h', a.newWithin[1])}
${card('new — last 7 days', a.newWithin[7])}
${card('new — last 28 days', a.newWithin[28])}
${card('active — last 7 days', a.activeWithin[7])}
${card('active — last 28 days', a.activeWithin[28])}
</div>
<p class="mut">“Active” = Auth <code>lastRefreshTime</code> (falling back to
<code>lastSignInTime</code>) within the window. Derived entirely from Auth metadata,
which carries no health data.</p>
<h2>Sync (Firestore <code>count()</code>)</h2>
<div class="grid">
${card('total logged days (all accounts)', metric(f.loggedDays))}
${card('accounts with synced settings', metric(f.accountsWithSyncedSettings))}
${card('local-only / never synced settings', metric(data.accountsLocalOnlyOrNeverSyncedSettings))}
${card('device cursor records', metric(f.deviceCursorDocs))}
${card('deletion markers (days)', metric(f.deletionMarkers))}
</div>
<p class="mut"><b>Definitions.</b> “Accounts with synced settings” counts
<code>users/{uid}/settings/current</code>, which is written at most once per account,
so it is an account count and not a document count — it is the cheapest honest proxy for
“has completed a sync”. An account that synced days but never edited a preference has no
such document (<code>SyncService._pushSettings</code> returns early when
<code>settingsUpdatedAt</code> is null), so “local-only / never synced settings” is an
upper bound on genuinely local-only accounts. “Device cursor records” counts devices, not
accounts.</p>
<h2>Account deletion</h2>
<div class="grid">
${card('pending deletion requests', metric(f.pendingDeletionRequests))}
${card('accounts not pending deletion', metric(data.accountsNotPendingDeletion))}
</div>
<p class="mut">Accounts with a marker at <code>deletionRequests/{uid}</code> are inside
the ~30-day grace window. <b>They wiped their device and believe their account is being
deleted.</b> They are flagged on every list and detail view. Note the purge job does not
exist yet, so their cloud data is still present.</p>`;
}

// --- roster ---------------------------------------------------------------

const pendingCell = (state) => {
  if (state === 'pending') return '<span class="flag">PENDING DELETION</span>';
  if (state === 'unknown') return '<span class="err">unknown</span>';
  return '<span class="mut">—</span>';
};

export function rosterView({ rows, nextPageToken, query }) {
  const search = `<form method="get" action="/users">
<label for="q">Find one account — exact email or uid</label>
<input type="text" id="q" name="q" value="${esc(query ?? '')}" placeholder="owner@example.com or a uid">
<button type="submit">Search</button>
<p class="note">Exact lookups only. There is deliberately no search over anything a user
logged — see the note on the records view.</p></form>`;

  if (rows.length === 0) {
    return `<h1>Users</h1>${search}<p class="mut">No accounts matched.</p>`;
  }

  const body = rows
    .map(
      (row) => `<tr>
<td><a href="/users/${encodeURIComponent(row.uid)}"><code>${esc(row.uid)}</code></a></td>
<td>${esc(row.email ?? '—')}${row.disabled ? ' <span class="flag">DISABLED</span>' : ''}</td>
<td>${esc(day(row.created))}</td>
<td>${esc(day(row.lastSeen))}</td>
<td>${pendingCell(row.pendingDeletion)}</td>
</tr>`,
    )
    .join('');

  const more = nextPageToken
    ? `<p><a href="/users?pageToken=${encodeURIComponent(nextPageToken)}">Next page →</a></p>`
    : '';

  return `<h1>Users</h1>${search}
<div class="overflow"><table>
<thead><tr><th>uid</th><th>email</th><th>created</th><th>last seen</th><th>deletion</th></tr></thead>
<tbody>${body}</tbody></table></div>${more}
<p class="mut">Roster from Firebase Auth <code>listUsers()</code>. This page shows no
health data of any kind. Note <code>users/{uid}</code> documents are never created by the
app, so a Firestore listing of that collection would return nothing.</p>`;
}

// --- account metadata -----------------------------------------------------

export function accountView(detail) {
  const uid = detail.uid;
  const d = detail.deletion;
  const banner =
    d.pending === true
      ? `<div class="banner"><b>This account has requested deletion.</b>
Requested ${esc(stamp(d.requestedAt))}; purge due ${esc(stamp(d.purgeAfter))}.
The user wiped their device and believes their account is being deleted. They can still
cancel. Treat their records accordingly.</div>`
      : d.pending === 'unknown'
        ? `<div class="banner">Deletion state could not be read: ${esc(d.error)}. Treat as possibly pending.</div>`
        : '';

  const authBlock = detail.auth
    ? `<dl class="day dl"><dt>email</dt><dd>${esc(detail.auth.email ?? '—')}</dd>
<dt>email verified</dt><dd>${detail.auth.emailVerified}</dd>
<dt>disabled</dt><dd>${detail.auth.disabled}</dd>
<dt>created</dt><dd>${esc(stamp(detail.auth.created))}</dd>
<dt>last seen</dt><dd>${esc(stamp(detail.auth.lastSeen))}</dd></dl>`
    : `<div class="banner">No Firebase Auth user for this uid${detail.authError ? `: ${esc(detail.authError)}` : ''}.
If Firestore documents exist below, this is orphaned data — the account-deletion purge
job does not exist yet, so a removed Auth user leaves its subtree behind.</div>`;

  const devices = Array.isArray(detail.devices)
    ? detail.devices.length === 0
      ? '<p class="mut">No device cursor documents. This account has not completed a cursor-advancing sync.</p>'
      : `<div class="overflow"><table><thead><tr><th>device id</th><th>logs cursor</th><th>deletions cursor</th></tr></thead><tbody>${detail.devices
          .map(
            (device) =>
              `<tr><td><code>${esc(device.deviceId)}</code></td><td>${esc(stamp(device.logsCursor))}</td><td>${esc(stamp(device.deletionsCursor))}</td></tr>`,
          )
          .join('')}</tbody></table></div>`
    : `<p class="err">Devices unavailable: ${esc(detail.devices.error)}</p>`;

  return `<h1>Account metadata</h1>
<p class="mut"><code>${esc(uid)}</code></p>
${banner}
<h2>Identity (Firebase Auth)</h2>${authBlock}
<h2>Documents (count aggregations)</h2>
<div class="grid">
${card('daily log documents', metric(detail.counts.dailyLogs))}
${card('deletion markers', metric(detail.counts.deletions))}
${card('device cursor docs', metric(detail.counts.devices))}
</div>
<p class="mut">Earliest logged day <b>${esc(detail.earliestLogDate ?? '—')}</b>,
latest <b>${esc(detail.latestLogDate ?? '—')}</b>. Both come from document <i>ids</i>
(<code>syncDocId</code> makes the id the ISO date) via a projection that requests no
fields — no log content was read to produce this page.</p>
<h2>Settings sync</h2>
${
  detail.settings
    ? `<dl class="day dl"><dt>settings updatedAt</dt><dd>${esc(stamp(detail.settings.updatedAt))}</dd>
<dt>settings syncedAt</dt><dd>${esc(stamp(detail.settings.syncedAt))}</dd></dl>
<p class="note">Only these two fields are read. The rest of that document holds
preferences including <code>pregnancyStartDate</code>, and the metadata view has no
business with it.</p>`
    : '<p class="mut">No <code>settings/current</code> document — this account has never pushed settings.</p>'
}
<h2>Devices</h2>${devices}
<h2>Health records</h2>
<p class="mut">Not shown here. Reading them is a separate, audited action.</p>
<p><a href="/users/${encodeURIComponent(uid)}/records">Open record browse →</a></p>`;
}

// --- record browse --------------------------------------------------------

export function reasonGateView({ uid, deletion, error }) {
  const banner =
    deletion?.pending === true
      ? `<div class="banner"><b>This account has requested deletion.</b> The user wiped
their device and believes their account is being deleted. Purge due
${esc(stamp(deletion.purgeAfter))}.</div>`
      : '';
  return `<h1>Record browse</h1>
<p class="mut"><code>${esc(uid)}</code></p>
${banner}
${error ? `<div class="banner">${esc(error)}</div>` : ''}
<div class="banner">You are about to read this person's menstrual-health records:
flow, symptoms, sexual activity, mood, free-text notes, basal body temperature and
ovulation-test results. An append-only audit record naming you, this account, the time
and your stated reason is written <b>before</b> any record is returned. If that write
fails, no records are shown.</div>
<form method="post" action="/users/${encodeURIComponent(uid)}/records">
<label for="reason">Why are you opening these records? (required)</label>
<textarea id="reason" name="reason" rows="3" required
 placeholder="e.g. support ticket #412 — user reports her March days are missing on a new phone"></textarea>
<button type="submit">Record the reason and show the days</button>
</form>
<p><a href="/users/${encodeURIComponent(uid)}">← Back to metadata (no health data, no audit gate)</a></p>`;
}

const tagList = (tags) => {
  const parts = [];
  if (tags.symptoms.length) {
    parts.push(`<dt>symptoms</dt><dd>${esc(tags.symptoms.join(', '))}</dd>`);
  }
  for (const group of tags.groups) {
    parts.push(`<dt>${esc(group.label)}</dt><dd>${esc(group.values.join(', '))}</dd>`);
  }
  for (const m of tags.metrics) {
    parts.push(`<dt>${esc(m.label)}</dt><dd>${esc(m.value)}</dd>`);
  }
  if (tags.unrecognised.length) {
    parts.push(
      `<dt>unrecognised keys</dt><dd>${esc(
        tags.unrecognised.map((entry) => `${entry.key}=${JSON.stringify(entry.value)}`).join(', '),
      )}</dd>`,
    );
  }
  return parts.join('');
};

const dayCard = (entry) => `<div class="day">
<h3>${esc(entry.date)}${entry.bleeding ? ' <span class="flag">bleeding</span>' : ''}</h3>
<dl>
<dt>flow</dt><dd>${esc(entry.flowLabel ?? '—')}</dd>
<dt>mood</dt><dd>${esc(entry.mood ?? '—')}</dd>
<dt>BBT</dt><dd>${esc(entry.bbt ?? '—')}</dd>
<dt>OPK / LH</dt><dd>${esc(entry.opk ?? '—')}</dd>
${tagList(entry.tags)}
<dt>notes</dt><dd>${esc(entry.notes ?? '—')}</dd>
<dt>created / updated</dt><dd>${esc(stamp(entry.createdAt))} / ${esc(stamp(entry.updatedAt))}</dd>
<dt>synced / device</dt><dd>${esc(stamp(entry.syncedAt))} / <code>${esc(entry.deviceId ?? '—')}</code></dd>
</dl></div>`;

export function recordsView({ uid, days, nextBefore, status, deletion, reason, deletions, total }) {
  const banner =
    deletion?.pending === true
      ? `<div class="banner"><b>Pending account deletion.</b> Purge due ${esc(stamp(deletion.purgeAfter))}.</div>`
      : '';

  const statusBlock = status
    ? `<dl class="day dl">
<dt>last logged day</dt><dd>${esc(status.lastLoggedDate ?? '—')} (${esc(status.lastLoggedDaysAgo ?? '—')} days ago)</dd>
<dt>last bleeding day</dt><dd>${esc(status.lastBleedingDate ?? '—')} (${esc(status.lastBleedingDaysAgo ?? '—')} days ago)</dd>
<dt>window</dt><dd>${esc(status.windowCoversDays)} days shown, oldest ${esc(status.oldestDateInWindow ?? '—')}</dd>
</dl>
<p class="note">Observed facts only — read straight off the documents. Nothing on this
page is estimated, predicted or inferred. The app's own Dart services compute where the
user is in her cycle and frame it carefully for her; a second implementation here would
drift from what she sees on her own screen, and would restate a calendar-method estimate
as though it were fact.</p>`
    : '<p class="mut">No days in this window.</p>';

  const deletionsBlock =
    deletions && deletions.length
      ? `<h2>Deleted days (markers)</h2><div class="overflow"><table>
<thead><tr><th>date</th><th>deleted at</th><th>synced at</th></tr></thead><tbody>${deletions
          .map(
            (entry) =>
              `<tr><td>${esc(entry.date)}</td><td>${esc(stamp(entry.deletedAt))}</td><td>${esc(stamp(entry.syncedAt))}</td></tr>`,
          )
          .join('')}</tbody></table></div>
<p class="note">Cross-device deletion markers. Dates only — the content of a deleted day
is gone from the server.</p>`
      : '';

  const more = nextBefore
    ? `<form method="post" action="/users/${encodeURIComponent(uid)}/records">
<input type="hidden" name="before" value="${esc(nextBefore)}">
<label for="reason2">Reason for the next page (required again)</label>
<textarea id="reason2" name="reason" rows="2" required>${esc(reason ?? '')}</textarea>
<button type="submit">Older days →</button>
<p class="note">Each page is a separate audited disclosure, so each needs its own record.</p>
</form>`
    : '';

  const reconcile =
    typeof total === 'number'
      ? `<p class="note">This account has <b>${total}</b> day documents in total
(<code>count()</code>); ${days.length} are shown on this page. Pages are ordered on the
<code>date</code> field, and a Firestore order filter silently excludes any document that
lacks it — so if the pages never add up to this total, that is the reason to look.</p>`
      : '';

  return `<h1>Records</h1>
<p class="mut"><code>${esc(uid)}</code> — this view was written to the audit log before it
was rendered.</p>
${banner}
<h2>Current status</h2>${statusBlock}
<h2>Days</h2>${reconcile}${days.map(dayCard).join('')}
${more}
${deletionsBlock}
<p><a href="/users/${encodeURIComponent(uid)}">← Back to metadata</a></p>`;
}

export function errorView(message) {
  return `<h1>Not available</h1><div class="banner">${esc(message)}</div>
<p><a href="/">← Dashboard</a></p>`;
}

export const _internals = { iso, day, stamp, metric };
