# Assistant reply images from Pexels — design

Date: 2026-09-26 · Status: approved in chat, awaiting spec review

## Intent

The owner wants every AI Assistant reply to carry a relevant stock photo, sourced from the
Pexels API, so the chat looks richer.

**Owner decisions (2026-09-26)**
- An image on **every** reply.
- The search term is the reply's **real topic**, for example "menstrual cramps relief". It
  is not a sanitised generic word.
- The app stays **8+**. The minimum age in onboarding does not change.
- No content filter. The Pexels API has no safe-search setting, and its content policy
  already excludes explicit imagery.

**Consequence the owner accepted.** Topic phrases from health conversations, including
minors' conversations, are sent to Pexels, a new third party. This must be disclosed, so
consent goes to v8 and `PRIVACY_POLICY.md` is updated. The project's copy rule requires it:
copy describes what the code does.

**Success criteria**
- Each answered reply shows one photo under the prose, with a "Photo by *Name* on Pexels"
  credit.
- A saved or synced conversation shows the same photo again when reopened, with no new
  search.
- A missing key, a Pexels failure or an image that won't load never breaks or delays the
  reply text beyond the 5-second lookup cap.

## Approach

The model writes the search term. `kAnalysisSystemInstruction` gains one clause: end every
reply with a final line `[image: <2–5 word topic of this reply>]`. This costs no extra
Gemini call.

Rejected alternatives:
- A second Gemini call per reply: doubles cost and slows every reply.
- The user's raw message as the query: worst relevance and the most sensitive text.

## Components

1. **`lib/services/pexels_client.dart`** (new). This is the seam.
   - `kPexelsApiKey = String.fromEnvironment('LUNA_PEXELS_KEY')`, read only here, and
     `pexelsAvailable`.
   - `PexelsClient.searchTop(String query) → Future<PexelsPhoto?>`:
     - `GET https://api.pexels.com/v1/search?query=<q>&per_page=1`, header
       `Authorization: <key>`
     - 5-second timeout
     - returns null on any non-200 (429 included), on an empty `photos` list, on a
       timeout, or on malformed JSON
     - never throws
   - `PexelsPhoto { id, src (photos[0].src.medium), photographer, photographerUrl, pageUrl }`.
   - Uses `dart:io` `HttpClient`, as `media_analyzer.dart` does. No new dependency.
2. **`lib/services/reply_image.dart`** (new, pure). Holds the marker format:
   - Unresolved tag, as the model writes it: a final line `[image: <query>]`.
   - Resolved marker, as stored: a final line `[[pexels <json>]]` with json
     `{"q","id","src","by","byUrl","page"}`. JSON so that any character in a name or query
     round-trips.
   - `splitReply(text) → (prose, ReplyImage?)`: handles a tag, a marker, neither, a
     malformed marker (prose kept, image null), and trailing whitespace.
   - `forModel(text)`: reduces a marker to `[image: <q>]` before replay, so the model never
     sees URLs or names.
3. **`ReplyImageResolver`** (in `lib/screens/assistant/`, owned by `LiveAssistantBackend`).
   - `resolve(reply, {fallbackQuery})`: strip the tag, search, and return the reply text
     with a resolved marker, or with the unresolved tag kept on failure.
   - The query is the model's tag. If the tag is missing, it is `fallbackQuery` (the
     user's question, cut to 60 characters).
   - The result is memoised per reply text. `persistTurn` (called inside `analyze`) and
     `send` (after `analyze`) share one search.
   - With `pexelsAvailable == false`: the tag is stripped and no search runs.
4. **Wiring.**
   - `LiveAssistantBackend.persistTurn` saves `resolve(answer)`.
   - `send` returns `resolve(prose)`, a memo hit.
   - The resume path passes `forModel(text)` to `seedConversation` for model turns.
5. **Display** (`analysis_chat_view.dart`, `_Bubble` for `ChatEntryKind.reply`).
   - Renders the prose from `splitReply`.
   - Below it, `Image.network(src)` with rounded corners.
   - The credit line appears only after the image loads. It links to `byUrl`, and "Pexels"
     links to `page`.
   - `errorBuilder` hides both the image and the credit.
   - Photos are never sent back to Gemini as attachments.
6. **Consent v8.**
   - `kCurrentConsentVersion = 8`.
   - The consent sheet adds: "A short topic phrase from each reply is sent to Pexels to
     find a photo."
   - `PRIVACY_POLICY.md` gets a Pexels paragraph.

## Error handling

| Case | Result |
|---|---|
| No `LUNA_PEXELS_KEY` | Feature off. The tag is stripped and no image is shown |
| The model omits the tag | Search uses the fallback query |
| Timeout, non-200 or 429, zero results, bad JSON | Reply saved with the unresolved tag. Nothing shown, never retried on reopen |
| Malformed stored marker | Prose shown, no image |
| Image load fails | Image and credit are hidden |

**Rate limits.** Pexels allows 200 requests an hour and 20,000 a month per key. The
existing 20-messages-a-day cap bounds the searches to at most 20 per user per day.

## Guardrail changes (deliberate)

- **`media_guardrails_test`, "only media_analyzer.dart makes an outbound HTTP request".**
  The allowlist becomes exactly `[media_analyzer.dart, pexels_client.dart]`. The test's own
  reason (`flutter_test`'s 400 mock hides real calls) is honoured, because the client is
  injected in every test.
- **New test:** `LUNA_PEXELS_KEY` is read in exactly one file.
- **`kAnalysisSystemInstruction`:** the existing refusal clauses are unchanged. The new
  image-line clause is asserted like the others.

## Testing

**Unit tests**
- `reply_image_test`: marker round-trip, including quotes, brackets, unicode and newlines
  in the query or name; each `splitReply` case; `forModel`.
- `pexels_client_test` uses an injected transport (a fake HTTP responder):
  - 200 with a photo
  - 200 with an empty list
  - 429
  - timeout
  - malformed JSON
  - no key

**Resolver tests**
- success
- failure keeps the tag
- fallback query
- the memo (one search for persist and send)
- key-off strips the tag

**Wiring and widget tests**
- **Backend:** the persisted model row contains the resolved marker, and the resumed
  replay contains only `[image: q]`.
- **Widget:** prose without the marker; image and credit present; an image failure hides
  both.
- **Consent:** the v8 test covers the Pexels disclosure.

**On the device** (manual; `flutter_tester` answers every real network call with 400):
- A real reply shows a photo and its credit.
- Reopening a chat shows the same photo.
- Airplane mode shows the reply with no image.

## Out of scope

- An age gate change.
- More than one image per reply.
- Caching image bytes to disk.
- Using Pexels video.
- Generating images with AI.
