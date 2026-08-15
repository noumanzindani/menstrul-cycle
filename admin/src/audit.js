// The append-only record of every time an operator looked at somebody's health
// data.
//
// ## Where it lives, and why that is safe without a rules change
//
// Top-level collection `adminAudit`. `firestore.rules` has NO
// `match /{document=**}` catch-all — see its "Default deny" section — so a path
// no rule names is denied to every client. `adminAudit` is named by no rule,
// therefore no app client can read it, list it, write to it or tamper with it.
// The Admin SDK bypasses rules, so this process can. That is the whole design:
// the panel needs ZERO change to `firestore.rules`, and the rules file stays
// byte-identical so all 29 existing emulator tests keep their exact meaning.
// `test/admin.test.mjs` asserts the client-side denial rather than assuming it.
//
// ## Why the write happens BEFORE the content is read
//
// An audit record written after a successful read is not an audit trail, it is
// a courtesy: a crash, a timeout, a killed container or a thrown renderer
// between the two loses the record and keeps the disclosure. Worse, an operator
// who wanted no trail could induce exactly that. So the order is: write the
// record, await it, and only then touch a single health document. If the write
// fails, the READ FAILS — no content, no partial page, nothing. Unavailable
// audit means unavailable data.
//
// ## Append-only
//
// Auto-id document + `.create()`, which fails if the id already exists, so no
// call can overwrite an earlier record. This module exposes no update and no
// delete, so nothing in this process can revise history through it.

import { FieldValue } from 'firebase-admin/firestore';

export const AUDIT_COLLECTION = 'adminAudit';

/** Views that disclose actual health content and so demand a stated reason. */
export const CONTENT_VIEWS = new Set(['record_browse', 'record_day']);

export class AuditError extends Error {}

/**
 * @param db a RAW (unwrapped) Firestore handle. This is the only writer in the
 *   process; everything else runs through `readOnly()`.
 */
export function createAuditLog(db, { serverTimestamp = FieldValue.serverTimestamp } = {}) {
  return {
    /**
     * Records one operator view. Resolves only once the record is durable.
     *
     * Throws — and therefore blocks the read — on a missing actor, a missing
     * target, or a missing reason for a content view.
     */
    async record({ actor, targetUid, view, reason, path = null, at = null }) {
      if (!actor) throw new AuditError('audit record has no actor');
      if (!targetUid) throw new AuditError('audit record has no target uid');
      if (!view) throw new AuditError('audit record has no view');

      const trimmed = String(reason ?? '').trim();
      if (CONTENT_VIEWS.has(view) && trimmed.length === 0) {
        // Not a formality. The reason is the only part of the record that a
        // later reader — the owner, an auditor, a regulator — can use to tell a
        // support ticket apart from curiosity.
        throw new AuditError(
          'a written reason is required before health records can be shown',
        );
      }

      const doc = db.collection(AUDIT_COLLECTION).doc();
      await doc.create({
        actor,
        targetUid,
        view,
        reason: trimmed,
        path,
        // Server-stamped: an audit trail's WHEN must not depend on the
        // container's clock, which the operator's own deploy controls.
        at: at ?? serverTimestamp(),
      });
      return doc.id;
    },
  };
}

/**
 * Runs [read] only after [audit.record] has durably resolved.
 *
 * The ordering guarantee lives HERE, in one function every content path calls,
 * rather than being re-implemented per route where one route could get it
 * backwards.
 */
export async function auditedRead(audit, entry, read) {
  await audit.record(entry);
  return read();
}
