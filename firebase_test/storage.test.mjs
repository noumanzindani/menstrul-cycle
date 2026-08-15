// Emulator tests for `storage.rules` — the boundary around uploaded media.
//
// Run with:  firebase_test/storage_run.sh
//
// This ruleset matters more than its size suggests. The bytes it guards are
// unencrypted photographs and video in a health app, and the Firebase project
// is shared with unrelated apps whose users all hold valid tokens. Every test
// below therefore uses `mallory` — a perfectly legitimate signed-in user of
// SOMEBODY's app — rather than an anonymous caller, because "is signed in" is
// not a boundary here and a suite that only tested anonymous access would pass
// against a ruleset that leaks everything.

import assert from 'node:assert/strict';
import { after, beforeEach, before, describe, test } from 'node:test';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  anonymous,
  assertAllowed,
  assertDenied,
  clearStorage,
  download,
  list,
  loadRules,
  remove,
  seed,
  upload,
  user,
} from './storage_emulator.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const RULES =
  process.env.LUNA_STORAGE_RULES_FILE ?? path.join(here, '..', 'storage.rules');

const alice = user('alice');
const mallory = user('mallory');
const nobody = anonymous();

const ID = '0123456789abcdef0123456789abcdef';
const ORIGINAL = `users/alice/media/${ID}/original.jpg`;
const THUMB = `users/alice/media/${ID}/thumb.jpg`;

const MB = 1024 * 1024;

before(async () => {
  await loadRules(RULES);
});
beforeEach(async () => {
  await clearStorage();
  await loadRules(RULES);
});
after(async () => {
  await clearStorage();
});

describe('the owner', () => {
  test('can upload, download and delete their own media', async () => {
    await assertAllowed(upload(alice, ORIGINAL), 'alice uploading her photo');
    await assertAllowed(download(alice, ORIGINAL), 'alice downloading it');
    await assertAllowed(remove(alice, ORIGINAL), 'alice deleting it');
  });

  test('can upload a thumbnail alongside the original', async () => {
    await assertAllowed(upload(alice, THUMB), 'alice uploading her thumbnail');
  });

  test('can LIST their own prefix — the orphan sweep depends on it', async () => {
    // Without this, a crash between "bytes uploaded" and "metadata document
    // written" leaves unencrypted media nothing can ever find or delete,
    // including the account purge. This is why the ruleset grants `list` to the
    // owner rather than denying it outright.
    await seed(ORIGINAL);
    await assertAllowed(
      list(alice, 'users/alice/media/'),
      'alice listing her own media prefix',
    );
  });

  test('can upload every accepted content type', async () => {
    for (const [type, name] of [
      ['image/jpeg', 'original.jpg'],
      ['image/png', 'original.png'],
      ['image/webp', 'original.webp'],
      ['image/heic', 'original.heic'],
      ['video/mp4', 'original.mp4'],
      ['video/quicktime', 'original.mov'],
    ]) {
      await assertAllowed(
        upload(alice, `users/alice/media/${ID}/${name}`, { contentType: type }),
        `alice uploading ${type}`,
      );
    }
  });
});

describe('another signed-in user', () => {
  test('CANNOT download somebody else\'s media', async () => {
    await seed(ORIGINAL);
    await assertDenied(download(mallory, ORIGINAL), "mallory downloading alice's photo");
  });

  test('CANNOT list somebody else\'s prefix', async () => {
    await seed(ORIGINAL);
    await assertDenied(
      list(mallory, 'users/alice/media/'),
      "mallory listing alice's media",
    );
  });

  test('CANNOT write into somebody else\'s prefix', async () => {
    await assertDenied(
      upload(mallory, ORIGINAL),
      "mallory uploading into alice's prefix",
    );
  });

  test('CANNOT delete somebody else\'s media', async () => {
    await seed(ORIGINAL);
    await assertDenied(remove(mallory, ORIGINAL), "mallory deleting alice's photo");
  });
});

describe('an unauthenticated caller', () => {
  test('CANNOT download a known object path', async () => {
    // The one that catches a bucket left on a permissive console default.
    await seed(ORIGINAL);
    await assertDenied(download(nobody, ORIGINAL), 'anonymous downloading media');
  });

  test('CANNOT upload', async () => {
    await assertDenied(upload(nobody, ORIGINAL), 'anonymous uploading media');
  });
});

describe('what the bucket will accept', () => {
  test('refuses a content type outside the allowlist', async () => {
    // Not malware scanning — the point is that this bucket must never be able
    // to SERVE `text/html` from a firebasestorage.app origin, which would be a
    // phishing page hosted on and attributed to the operator.
    for (const type of [
      'text/html',
      'application/pdf',
      'application/octet-stream',
      'image/svg+xml',
    ]) {
      await assertDenied(
        upload(alice, ORIGINAL, { contentType: type }),
        `alice uploading ${type}`,
      );
    }
  });

  test('refuses a partial content-type match', async () => {
    // The allowlist is anchored. Same rule, and the same reasoning, as
    // `mediaKindFor` in lib/services/media_limits.dart.
    await assertDenied(
      upload(alice, ORIGINAL, { contentType: 'text/html;image/jpeg' }),
      'alice smuggling text/html past the image check',
    );
  });

  test('refuses an image over the image ceiling', async () => {
    await assertDenied(
      upload(alice, ORIGINAL, { bytes: 12 * MB + 1, contentType: 'image/jpeg' }),
      'alice uploading a 12MB+ image',
    );
  });

  test('applies the VIDEO ceiling to video, not the image one', async () => {
    // The discriminating half: a size that must be refused as an image and
    // allowed as a video, proving the two ceilings are genuinely separate.
    await assertAllowed(
      upload(alice, `users/alice/media/${ID}/original.mp4`, {
        bytes: 12 * MB + 1,
        contentType: 'video/mp4',
      }),
      'alice uploading a 12MB+ video',
    );
  });

  test('refuses an arbitrary file name', async () => {
    // Object paths reach access logs, audit logs and billing exports, where a
    // filename is health data.
    await assertDenied(
      upload(alice, `users/alice/media/${ID}/IMG_ultrasound_12wk.jpg`),
      'alice uploading under her own filename',
    );
  });

  test('refuses arbitrary client-written custom metadata', async () => {
    await assertDenied(
      upload(alice, ORIGINAL, { metadata: { metadata: { note: 'smuggled' } } }),
      'alice writing custom object metadata',
    );
  });

  test('CHARACTERISATION: rules do NOT stop a client minting a download token',
    async () => {
      // This began as a guarantee and is recorded as a defect instead, because
      // that is what the emulator actually does.
      //
      // `noClientMetadata()` was written to block `firebaseStorageDownloadTokens`
      // — a client-chosen value that becomes a permanent, rules-bypassing bearer
      // URL for the object. The service lifts that key out of the metadata map
      // BEFORE rules run, so the map the rule inspects is already empty and the
      // upload is allowed. The token in the response below is the one the caller
      // chose.
      //
      // Recorded rather than deleted so nobody reads storage.rules and concludes
      // the hole is closed. The real defences are: the app never calls
      // getDownloadURL(), firestore.rules refuses to STORE a URL, and reads go
      // through the authenticated SDK. Re-check against production Storage
      // before relying on any of this.
      const result = await upload(alice, ORIGINAL, {
        metadata: {
          metadata: { firebaseStorageDownloadTokens: 'chosen-token' },
        },
      });
      assert.equal(result.status, 200, 'expected the upload to be permitted');
      assert.match(
        result.body,
        /chosen-token/,
        'the caller-chosen download token was not honoured — re-read the rule, '
          + 'this characterisation may now be out of date (which would be good news)',
      );
    });

  test('CHARACTERISATION: `allow update: if false` does NOT stop an overwrite',
    async () => {
      // Also a defect, also recorded rather than asserted away. A re-upload to
      // an existing path is evaluated as a CREATE — a new object generation —
      // so it never reaches the `update` rule.
      //
      // Harmless in practice because `newMediaId()` is random per upload, so
      // the app never reuses a path, and every path is uid-scoped so a client
      // can only overwrite its own bytes. Not harmless to BELIEVE, which is why
      // it is written down.
      await seed(ORIGINAL);
      await assertAllowed(
        upload(alice, ORIGINAL),
        'alice overwriting her own object (documented gap, not a guarantee)',
      );
    });
});

describe('paths outside the model', () => {
  test('a listing at users/ is denied — no roster of who has uploaded', async () => {
    await seed(ORIGINAL);
    await assertDenied(list(alice, 'users/'), 'alice listing every account');
  });

  test('an object outside users/{uid}/media is denied', async () => {
    await assertDenied(
      upload(alice, 'scratch/anything.jpg'),
      'alice writing outside the modelled path',
    );
  });

  test('a deeper path under a media folder is denied', async () => {
    await assertDenied(
      upload(alice, `users/alice/media/${ID}/nested/original.jpg`),
      'alice writing below the modelled depth',
    );
  });
});

describe('agreement with the client', () => {
  test('the ceilings match lib/services/media_limits.dart', async () => {
    // The Dart caps are a UX refusal; these are the enforcing copy, because the
    // API key ships inside the APK. They must not drift apart.
    const fs = await import('node:fs');
    const source = fs.readFileSync(
      path.join(here, '..', 'lib', 'services', 'media_limits.dart'),
      'utf8',
    );
    const image = source.match(/kMaxImageBytes = (\d+) \* 1024 \* 1024/);
    const video = source.match(/kMaxVideoBytes = (\d+) \* 1024 \* 1024/);
    assert.ok(image && video, 'could not parse the Dart caps');

    const rules = fs.readFileSync(RULES, 'utf8');
    assert.match(
      rules,
      new RegExp(`request\\.resource\\.size <= ${image[1]} \\* 1024 \\* 1024`),
      'the image ceiling in storage.rules does not match kMaxImageBytes',
    );
    assert.match(
      rules,
      new RegExp(`request\\.resource\\.size <= ${video[1]} \\* 1024 \\* 1024`),
      'the video ceiling in storage.rules does not match kMaxVideoBytes',
    );
  });
});
