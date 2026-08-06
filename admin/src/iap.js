// Google Cloud IAP is the front door. There is no login page in this service,
// no password form, no session cookie and no auth endpoint — deliberately.
//
// ## Why the JWT assertion and not the email header
//
// IAP sets two things on every request it forwards:
//
//   x-goog-authenticated-user-email    accounts.google.com:owner@example.com
//   x-goog-iap-jwt-assertion           a short-lived ES256 JWT signed by Google
//
// The first is a plain string. If the Cloud Run service is ever reachable
// without going through IAP — a direct `*.run.app` URL with the ingress setting
// wrong, a misconfigured load balancer, an internal caller — then anyone can
// send that header and be "the owner". The second is cryptographically signed
// and bound to this specific service via its `aud` claim, so forging it is
// forging a Google signature.
//
// This module therefore verifies the ASSERTION and ignores the email header
// entirely. That does not make direct exposure safe (see the README) — an
// unverified path is still a path — but it removes the trivial spoof.
//
// No JWT library: Node's built-in `crypto` verifies ES256 directly, and this
// project's dependency rule is `firebase-admin` and `express`, nothing else.

import crypto from 'node:crypto';

export const IAP_JWT_HEADER = 'x-goog-iap-jwt-assertion';

/** Google's IAP signing keys, as a JWK Set. */
export const IAP_JWKS_URL = 'https://www.gstatic.com/iap/verify/public_key-jwk';

/** IAP's issuer claim. Fixed by Google. */
export const IAP_ISSUER = 'https://cloud.google.com/iap';

/** A leeway for clock skew between Google's signer and this container. */
const CLOCK_SKEW_SECONDS = 60;

/** Thrown when a request cannot be attributed to a verified identity. */
export class IdentityError extends Error {}

const decodeSegment = (segment) =>
  JSON.parse(Buffer.from(segment, 'base64url').toString('utf8'));

/**
 * Verifies an IAP JWT assertion and returns its verified claims.
 *
 * Every check below is load-bearing:
 *
 * - `alg` must be `ES256`. Accepting the token's own `alg` blindly is the
 *   classic JWT break: `none` verifies trivially, and `HS256` lets the public
 *   key be used as an HMAC secret.
 * - the signature must verify against a key from [jwks] matching `kid`.
 * - `iss` must be IAP's. A Google-signed token from some other Google service
 *   is not an IAP assertion.
 * - `aud` must equal [audience] EXACTLY. This is what binds the token to THIS
 *   service; without it, an assertion minted for any other IAP-protected
 *   service in any project would be accepted here.
 * - `exp`/`iat` must bracket now. IAP assertions live minutes; a replayed old
 *   one must not work.
 * - `email` must be present. IAP only omits it for service-account callers,
 *   which this panel does not have.
 */
export function verifyIapAssertion(token, { audience, jwks, now = Date.now() }) {
  if (!token) throw new IdentityError('no IAP assertion header present');
  if (!audience) throw new IdentityError('no IAP audience configured');

  const parts = String(token).split('.');
  if (parts.length !== 3) throw new IdentityError('malformed IAP assertion');
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  let header;
  let payload;
  try {
    header = decodeSegment(encodedHeader);
    payload = decodeSegment(encodedPayload);
  } catch {
    throw new IdentityError('unreadable IAP assertion');
  }

  if (header.alg !== 'ES256') {
    throw new IdentityError(`unexpected assertion algorithm: ${header.alg}`);
  }

  const jwk = (jwks?.keys ?? []).find((key) => key.kid === header.kid);
  if (!jwk) throw new IdentityError('IAP assertion signed by an unknown key');

  const signature = Buffer.from(encodedSignature, 'base64url');
  // ES256 signatures in JWS are the raw r‖s pair, not the DER encoding
  // `crypto.verify` assumes by default.
  const signed = crypto.verify(
    'sha256',
    Buffer.from(`${encodedHeader}.${encodedPayload}`),
    {
      key: crypto.createPublicKey({ key: jwk, format: 'jwk' }),
      dsaEncoding: 'ieee-p1363',
    },
    signature,
  );
  if (!signed) throw new IdentityError('IAP assertion signature is invalid');

  if (payload.iss !== IAP_ISSUER) {
    throw new IdentityError(`unexpected assertion issuer: ${payload.iss}`);
  }
  if (payload.aud !== audience) {
    throw new IdentityError('IAP assertion was minted for another service');
  }

  const seconds = Math.floor(now / 1000);
  if (typeof payload.exp !== 'number' || payload.exp + CLOCK_SKEW_SECONDS < seconds) {
    throw new IdentityError('IAP assertion has expired');
  }
  if (typeof payload.iat !== 'number' || payload.iat - CLOCK_SKEW_SECONDS > seconds) {
    throw new IdentityError('IAP assertion is not valid yet');
  }
  if (!payload.email) throw new IdentityError('IAP assertion carries no email');

  return { email: String(payload.email), subject: payload.sub ?? null };
}

/** Fetches and caches Google's IAP JWK Set. */
export function createIapKeyFetcher({ url = IAP_JWKS_URL, ttlMs = 3600_000 } = {}) {
  let cached = null;
  let fetchedAt = 0;
  return async function fetchKeys(now = Date.now()) {
    if (cached && now - fetchedAt < ttlMs) return cached;
    const response = await fetch(url);
    if (!response.ok) {
      throw new IdentityError(`could not fetch IAP keys: HTTP ${response.status}`);
    }
    cached = await response.json();
    fetchedAt = now;
    return cached;
  };
}

/**
 * Express middleware: verified IAP identity, then the allowlist.
 *
 * The allowlist is defence in depth, not the primary control — IAP is. It
 * exists because IAP's own access policy is edited in a different console by a
 * different mechanism, and a widened IAP policy (an accidental
 * `allAuthenticatedUsers`, a group that gained a member) should not silently
 * widen this panel. Two independent things now have to be wrong.
 *
 * [devIdentity], when present, skips verification entirely. `readConfig`
 * only ever populates it when `FIRESTORE_EMULATOR_HOST` is also set, so it
 * cannot be reached against a real database.
 */
export function requireAdminIdentity({
  audience,
  adminEmails,
  fetchKeys,
  devIdentity = null,
  now = () => Date.now(),
}) {
  return function identityMiddleware(req, res, next) {
    const attribute = async () => {
      if (devIdentity) return { email: devIdentity, subject: 'dev' };
      const jwks = await fetchKeys();
      return verifyIapAssertion(req.get(IAP_JWT_HEADER), {
        audience,
        jwks,
        now: now(),
      });
    };

    attribute()
      .then((identity) => {
        const email = identity.email.toLowerCase();
        if (!adminEmails.has(email)) {
          // The address is deliberately not echoed back: this response is
          // reachable by anyone IAP lets through, and the allowlist's contents
          // are not their business.
          res.status(403).type('text/plain').send('Not an authorised operator.');
          return;
        }
        req.actor = email;
        next();
      })
      .catch((error) => {
        const message =
          error instanceof IdentityError ? error.message : 'identity check failed';
        res.status(401).type('text/plain').send(`Unauthenticated: ${message}`);
      });
  };
}
