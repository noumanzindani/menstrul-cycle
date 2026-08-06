// A structurally read-only view of a Firestore handle.
//
// The Admin SDK bypasses `firestore.rules` completely. That is why this panel
// needs no rule change at all — and it is also why nothing server-side stops a
// stray `.set()` from rewriting somebody's menstrual log. An operator write to
// a health record is unfalsifiable from the user's side: they would see a day
// they never logged and have no way to tell it apart from their own entry.
//
// So the handle the views and queries receive is wrapped: every mutating method
// throws before it reaches the network, and the wrapper propagates through
// `collection()`, `doc()`, `where()`, snapshots and `snapshot.ref`, so there is
// no path back to a raw reference. The audit log is written through a SEPARATE,
// unwrapped handle (see `audit.js`), which is the only writer in the process.
//
// This is a guard, not a proof — but it converts "we were careful" into "the
// call throws", and `test/admin.test.mjs` asserts the throw on every shape.

/**
 * Methods that write, or that hand back a builder able to write.
 *
 * `batch`, `bulkWriter` and `runTransaction` are included because each returns
 * an object holding its own unwrapped references; blocking only `set`/`delete`
 * would leave three open doors.
 */
export const MUTATING_METHODS = new Set([
  'set',
  'update',
  'delete',
  'create',
  'add',
  'batch',
  'bulkWriter',
  'runTransaction',
  'recursiveDelete',
  'deleteAll',
  'bundle',
]);

export class ReadOnlyViolation extends Error {}

const isWrappable = (value) =>
  value !== null &&
  typeof value === 'object' &&
  (typeof value.collection === 'function' ||
    typeof value.doc === 'function' ||
    typeof value.where === 'function' ||
    typeof value.ref === 'object' ||
    Array.isArray(value.docs));

const isThenable = (value) =>
  value !== null && typeof value === 'object' && typeof value.then === 'function';

/**
 * Wraps [target] so that any mutating call throws.
 *
 * [label] is only for the error message; it names the thing that was about to
 * be written so a violation is obvious in a stack trace.
 */
export function readOnly(target, label = 'firestore') {
  if (target === null || typeof target !== 'object') return target;

  // Whatever a call hands back — a reference, a query, a snapshot, a promise of
  // one, or an array of them — comes back wrapped too.
  const wrap = (result, resultLabel) => {
    if (isThenable(result)) return result.then((value) => wrap(value, resultLabel));
    if (Array.isArray(result)) {
      return result.map((entry, index) =>
        isWrappable(entry) ? readOnly(entry, `${resultLabel}[${index}]`) : entry,
      );
    }
    return isWrappable(result) ? readOnly(result, resultLabel) : result;
  };

  return new Proxy(target, {
    get(object, property, receiver) {
      if (typeof property === 'string' && MUTATING_METHODS.has(property)) {
        return () => {
          throw new ReadOnlyViolation(
            `read-only Firestore handle: ${label}.${property}() is forbidden. ` +
              'The operator panel never writes health data.',
          );
        };
      }

      const value = Reflect.get(object, property, object);

      if (typeof value === 'function') {
        return (...args) => wrap(value.apply(object, args), `${label}.${String(property)}`);
      }
      // `snapshot.ref` and `snapshot.docs` are plain properties, not methods —
      // and `ref` is a fully-powered DocumentReference. Missing them would
      // leave the easiest escape hatch of all wide open.
      if (property === 'ref') return readOnly(value, `${label}.ref`);
      if (property === 'docs' && Array.isArray(value)) {
        return value.map((entry, index) => readOnly(entry, `${label}.docs[${index}]`));
      }
      return value;
    },
  });
}
