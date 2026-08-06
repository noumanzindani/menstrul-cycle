// The Express app.
//
// Assembled from injected dependencies so the whole surface is testable against
// the emulator without a network, a real IAP, or a real Google account.
//
// Route map:
//
//   GET  /healthz                      liveness only, no identity, no data
//   GET  /                             dashboard      — aggregations + Auth only
//   GET  /users                        roster         — Auth only, no health data
//   GET  /users/:uid                   metadata       — counts/dates/cursors, audited
//   GET  /users/:uid/records           reason gate    — a form, NO content
//   POST /users/:uid/records           records        — audited BEFORE content
//
// Record content is behind POST on purpose. A GET would make disclosure a
// linkable, bookmarkable, prefetchable, referrer-leaking action that carries no
// operator-supplied reason; requiring a form post means the reason is
// structurally impossible to skip.

import express from 'express';

import { auditedRead } from './audit.js';
import { accountDetail, deletionState } from './account.js';
import { browseDays, currentStatus, dayCount, recentDeletions } from './records.js';
import { collectDashboard } from './stats.js';
import { findAccount, listRoster } from './roster.js';
import {
  accountView,
  dashboardView,
  errorView,
  page,
  recordsView,
  reasonGateView,
  rosterView,
} from './views.js';

/**
 * No script, no styles from anywhere, no framing, no referrer, no caching.
 *
 * `no-store` matters more than it looks: a shared or corporate proxy caching a
 * page of menstrual-health records is a second, unaudited copy of the exact
 * data this panel logs every read of.
 */
export function securityHeaders(_req, res, next) {
  res.setHeader(
    'Content-Security-Policy',
    "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
  );
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Cache-Control', 'no-store, max-age=0');
  next();
}

/**
 * Rejects a cross-origin form post.
 *
 * The panel holds no cookies and no session, so classic CSRF cannot forge an
 * authenticated request — IAP's own credential is what authenticates, and a
 * browser will attach it. That is precisely the gap: a page on another origin
 * could POST here and cause a real, audited disclosure attributed to the
 * operator, with an attacker-chosen reason. The response is unreadable
 * cross-origin, but the read still happened and the audit log still says the
 * operator did it. Same-origin only.
 */
export function sameOriginOnly(req, res, next) {
  if (req.method !== 'POST') return next();
  const origin = req.get('origin');
  if (!origin) return next(); // no Origin header: not a browser form post
  const host = req.get('host');
  let originHost;
  try {
    originHost = new URL(origin).host;
  } catch {
    originHost = null;
  }
  if (originHost && host && originHost === host) return next();
  res.status(403).type('text/plain').send('Cross-origin request refused.');
  return undefined;
}

const asyncRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res)).catch(next);

/**
 * @param deps.db          a READ-ONLY Firestore handle (see `readonly.js`)
 * @param deps.auth        firebase-admin Auth
 * @param deps.audit       the audit log, backed by a separate WRITABLE handle
 * @param deps.identity    express middleware that sets `req.actor`
 */
export function createApp({ auth, db, audit, identity, config, now = () => Date.now() }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(securityHeaders);
  app.use(express.urlencoded({ extended: false, limit: '16kb' }));

  app.get('/healthz', (_req, res) => res.type('text/plain').send('ok'));

  app.use(identity);
  app.use(sameOriginOnly);

  const render = (res, actor, title, body, status = 200) =>
    res.status(status).type('html').send(page({ title, actor, body }));

  app.get(
    '/',
    asyncRoute(async (req, res) => {
      const data = await collectDashboard({
        auth,
        db,
        now: now(),
        max: config.maxRosterSweep,
      });
      render(res, req.actor, 'Dashboard', dashboardView(data));
    }),
  );

  app.get(
    '/users',
    asyncRoute(async (req, res) => {
      const query = req.query.q ? String(req.query.q) : '';
      const result = query
        ? await findAccount({ auth, db, query })
        : await listRoster({
            auth,
            db,
            pageToken: req.query.pageToken ? String(req.query.pageToken) : undefined,
            pageSize: config.pageSize,
          });
      render(res, req.actor, 'Users', rosterView({ ...result, query }));
    }),
  );

  app.get(
    '/users/:uid',
    asyncRoute(async (req, res) => {
      const uid = String(req.params.uid);
      // Metadata is audited too — the operator looked at a specific person's
      // account, and that is worth recording — but no reason is demanded. The
      // friction belongs on the door that discloses content; putting it here
      // as well would push operators toward the records page for questions the
      // metadata page answers.
      const detail = await auditedRead(
        audit,
        { actor: req.actor, targetUid: uid, view: 'account_metadata', path: req.path },
        () => accountDetail({ auth, db, uid }),
      );
      render(res, req.actor, 'Account', accountView(detail));
    }),
  );

  app.get(
    '/users/:uid/records',
    asyncRoute(async (req, res) => {
      const uid = String(req.params.uid);
      // The gate itself reads only the deletion marker — a uid and two
      // timestamps — so the warning can be shown before any content decision.
      const deletion = await deletionState(db, uid);
      render(res, req.actor, 'Record browse', reasonGateView({ uid, deletion }));
    }),
  );

  app.post(
    '/users/:uid/records',
    asyncRoute(async (req, res) => {
      const uid = String(req.params.uid);
      const reason = String(req.body?.reason ?? '');
      const before = req.body?.before ? String(req.body.before) : null;

      if (reason.trim().length === 0) {
        const deletion = await deletionState(db, uid);
        render(
          res,
          req.actor,
          'Record browse',
          reasonGateView({
            uid,
            deletion,
            error: 'A reason is required. No records were read.',
          }),
          400,
        );
        return;
      }

      let result;
      try {
        // `auditedRead` writes the audit record and AWAITS it; only then does
        // the reader run. A rejected audit write therefore means the fetch
        // never happens at all — not that it happens and goes unlogged.
        result = await auditedRead(
          audit,
          {
            actor: req.actor,
            targetUid: uid,
            view: 'record_browse',
            reason,
            path: req.path,
          },
          async () => {
            const [page_, deletion, deletions, total] = await Promise.all([
              browseDays(db, uid, { before }),
              deletionState(db, uid),
              recentDeletions(db, uid),
              dayCount(db, uid),
            ]);
            return { page: page_, deletion, deletions, total };
          },
        );
      } catch (error) {
        // Fail closed, loudly, with no content. "Unavailable audit log means
        // unavailable data" is the entire contract.
        render(
          res,
          req.actor,
          'Record browse',
          errorView(
            'The audit record could not be written, so no health records were read. ' +
              `Reason: ${error?.message ?? error}`,
          ),
          503,
        );
        return;
      }

      render(
        res,
        req.actor,
        'Records',
        recordsView({
          uid,
          days: result.page.days,
          nextBefore: result.page.nextBefore,
          status: currentStatus(result.page.days, { now: now() }),
          deletion: result.deletion,
          deletions: result.deletions,
          total: result.total,
          reason,
        }),
      );
    }),
  );

  // eslint-disable-next-line no-unused-vars -- Express identifies error
  // handlers by arity; dropping `next` turns this into a normal middleware and
  // errors would surface as the default HTML stack trace instead.
  app.use((error, req, res, _next) => {
    // Never echo the error body into the page beyond its message, and never log
    // a document's contents: they are menstrual-health data.
    res
      .status(500)
      .type('html')
      .send(
        page({
          title: 'Error',
          actor: req.actor,
          body: errorView(String(error?.message ?? error)),
        }),
      );
  });

  return app;
}
