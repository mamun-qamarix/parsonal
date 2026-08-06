# Implementation Decisions

This file records reasonable choices made where `project.md` was ambiguous,
per §13 of the spec ("make the most reasonable implementation choice and
note your assumption here rather than stopping to ask").

## 1. End-to-end encryption design

**Decision:** The server (FastAPI + PostgreSQL + media storage) never sees
plaintext content or an encryption key. Encryption/decryption happens
entirely on-device in the Flutter app.

- During onboarding, the Admin Panel generates a random 256-bit **Vault
  Master Key (VMK)** and embeds it (base64) inside the one-time setup
  code/QR, alongside the server address.
- Both spouses' apps read the VMK from the setup code during onboarding and
  store it in OS-backed secure storage (Android Keystore via
  `flutter_secure_storage`), never transmitted again after initial setup.
- Per-content symmetric keys are derived from the VMK via HKDF-SHA256 with
  a random per-item salt; each item is encrypted with AES-256-GCM
  (authenticated encryption) using a random 96-bit nonce.
- Chat messages are encrypted the same way before being sent over the
  WebSocket; the server only relays/stores ciphertext + minimal metadata
  needed to route and order messages (sender id, timestamp, content type).
- Media (photo/video/voice/files) is encrypted client-side before upload;
  the server stores encrypted blobs only. Thumbnails are generated
  client-side from the original file, then also encrypted before upload
  (the server cannot generate previews from ciphertext).
- Consequence: the server cannot search/filter by content text. Category,
  favorite flag, timestamps, content-type and view counts are stored as
  plaintext metadata (not sensitive) so the UI can list/sort/filter without
  server-side decryption.

## 2. Database schema management

**Decision:** Use SQLAlchemy models with `Base.metadata.create_all()` on
startup rather than a full Alembic migration history. This is a two-user,
self-hosted app with no multi-environment migration story; a single schema
bootstrap is simpler and sufficient. Alembic can be added later if the
schema needs to evolve after data exists in the field.

## 3. Setup code contents

**Decision:** The setup code (shown as text + QR) encodes a JSON payload,
base64-encoded: `{"server": "<https url>", "code": "<one-time token>",
"vmk": "<base64 32-byte key>"}`. The one-time token is single-use per role
claim (husband/wife) and expires after 24 hours or first successful use per
role.

## 4. Push notification transport

**Decision:** Firebase Cloud Messaging (FCM) is used only as a "wake up and
sync" signal (generic payload, no content, per §7). The backend stores an
FCM token per device (submitted by the app) and only requires the FCM
server key at final deployment (see project.md §14) — the app and backend
both function fully over direct WebSocket push while the app is in
foreground/background-connected; FCM is the fallback for killed-app state.

## 5. "Favorite Lines / Our Phrases" toggle default

**Decision:** Default **ON**. It reuses the same reaction/comment/rating
infrastructure as other content types and is core to the "halal alternative"
purpose of the app, so enabling it by default fits the product intent. It's
a per-deployment Settings toggle either spouse can turn off later.

## 6. Auth token model

**Decision:** Short-lived JWT access tokens (15 min) + long-lived refresh
tokens stored in secure storage, bound to a device id. Full re-auth
(password + face) is required after the configurable auto-lock inactivity
timeout, not just a token refresh.

## 7. Face verification service

**Decision:** Use [CompreFace](https://github.com/exadel-inc/CompreFace)
(self-hosted, Docker, Apache-2.0) for face embedding/recognition. Liveness
(blink detection) is implemented client-side in Flutter using
`google_mlkit_face_detection` (on-device ML Kit, no cloud calls) to detect
eye-open/eye-closed transitions during a short capture sequence; the
resulting "confirmed live" frame is what's submitted to CompreFace for
enrollment/verification. This keeps liveness fully on-device and only sends
a single verified frame to the self-hosted recognition service.

## 8. Voice notes & file attachments in chat

**Decision:** Voice notes recorded client-side (AAC), encrypted, uploaded
like any other media attachment. Chat file attachments capped at 50MB
(configurable in backend `.env`) to keep VPS storage predictable.

## 9. CompreFace API key provisioning

**Decision:** CompreFace's admin UI (`compreface-fe`) is intentionally bound
to `127.0.0.1:8085` only (not exposed via Caddy/public internet), to keep
the attack surface minimal.

`install.sh` now *attempts* to fully automate provisioning (organization →
application → recognition service → API key → written into `.env` →
backend restarted) via `backend/scripts/provision_compreface.py`, so most
deployments need zero manual steps for this. This automation talks to
CompreFace's own console API (org/app/model creation), which — unlike its
*recognition* API (`/api/v1/recognition/...`, stable and documented, used
by `app/services/face_verify.py` for every enroll/verify call) — has no
formal public contract and could differ across CompreFace versions. There
was no live CompreFace instance available to test the provisioning script
against while building this, so it's shipped as best-effort: every step is
guarded, the resulting key is verified against the real recognition API
before being trusted, and any failure exits non-zero without touching
`.env` rather than half-provisioning something.

If automation fails, `install.sh` falls back to printing the **one manual,
one-time, SSH-tunnel-only step** (documented step-by-step in `README.md`):
tunnel to port 8085, create an account + application + recognition service
in the CompreFace UI, copy the generated API key into `.env` as
`COMPREFACE_RECOGNITION_API_KEY`, then `docker compose up -d backend`.
Either way, everything else in the app requires zero further manual steps.

## 10. Decrypted video playback uses a private temp file

**Decision:** `video_player` has no in-memory/byte-buffer data source, so
`DecryptedVideoPlayer` decrypts a video into the app's private temp
directory (never shared storage, never accessible to other apps on modern
Android/iOS sandboxing) just long enough to play it, and deletes the file
on dispose. Photos and voice notes are handled fully in-memory
(`Image.memory`, byte buffers) with no disk touch. This is the one
deliberate exception to "ciphertext only" leaving memory, and only ever
touches this app's own sandboxed storage.

## 11. Screenshot blocking implemented natively, not via a plugin

**Decision:** The `screen_protector` pub package's Android build script
assumes AGP 9+ always means Kotlin is compiled via AGP's built-in support,
but this project (like several other plugins it depends alongside —
`camera`, `mobile_scanner`, `record`) still needs the classic Kotlin Gradle
Plugin applied, so builtInKotlin is disabled project-wide; that made
`screen_protector`'s own Kotlin file silently not compile. Rather than pull
in a workaround, `FLAG_SECURE` is set directly in `MainActivity.kt`'s
`onCreate` (a few lines, project.md §6's screenshot/recording block and
recent-apps-thumbnail block), removing the dependency entirely. The
background blur/cover overlay (all platforms) is handled in
`AppLockGuard` purely with Flutter's `WidgetsBindingObserver`, no plugin
needed there either.

## 12. Disabled Android backup / device-to-device data transfer

**Decision:** `android:allowBackup="false"` plus a `dataExtractionRules`
XML excluding `sharedpref`/`database`/`file` domains from both cloud
backup and Android 12+'s "copy your data from old phone" transfer flow.

Found in the field: a spouse setting up a new phone used Android's
device-transfer feature to copy data from another phone that already had
this app installed, and it copied over the app's local storage
(`flutter_secure_storage`-backed session: access/refresh tokens, stored
role, and the vault master key) — so the new phone opened straight to a
password-only login screen for the WRONG role, never showing onboarding.
Since this app's local storage holds real auth material and the vault's
E2E encryption key, it must never move between physical devices except
through the explicit setup-code flow (project.md §5's "two spouses can set
up from two completely separate physical phones" — implicitly, never via
OS-level cloning). This is also just a correct default for any app storing
credentials, independent of the bug it happened to surface.

## 13. Auth model changed: password + TOTP mandatory, face optional

**Decision (superseding project.md §6's "password and face verification,
both required every time"):** based on real device testing, the product
owner changed the mandatory second factor from face verification to a
TOTP authenticator code (Google Authenticator / Authy / etc — standard
`pyotp`-based 6-digit rotating code). Face verification becomes an
opt-in extra step, toggled on/off from Settings/Profile.

- `Spouse.totp_secret` is generated at claim time; `totp_confirmed` only
  flips true once the spouse enters one valid code back (proving they
  actually saved it in an authenticator app) via `/auth/totp/setup-confirm`.
- Login is now: password → TOTP code → (only if
  `face_verification_enabled`) face capture → access+refresh tokens.
- `/auth/face/enroll` enrolls AND enables in one step (first-time setup).
  `/auth/face/enable` / `/auth/face/disable` toggle it afterward without
  re-registering (unless never enrolled, which requires enroll again).
- Password reset's "both spouses must independently verify" step now uses
  each spouse's TOTP code instead of face (universally available, since
  face is optional) — `/auth/password-reset/verify` replaces the old
  `/verify-face` endpoint.
- This is a breaking schema change (new `Spouse` columns) on top of
  `Base.metadata.create_all()`-only migrations (§2) — a deployment with
  an existing `spouses` table must have its database volume reset for the
  new columns to exist; see README.md.

## 14. Onboarding survives being backgrounded

**Decision:** found in the field: a spouse switched away from the app
mid-onboarding (to install/open Google Authenticator) and returned to find
themselves bounced to a password-only login screen that could never
succeed, because `AppLockGuard` unconditionally forced `SessionState.locked`
on every backgrounding — including mid-setup, before TOTP was ever
confirmed, leaving no way back into the TOTP setup screen. Two fixes:

- `SessionProvider.lock()` now only actually locks when the session was
  already `authenticated`; backgrounding during any onboarding/login-in-
  progress state leaves that state untouched, so returning to the app
  resumes exactly where it left off.
- `bootstrap()` (cold start) now asks `GET /auth/me` whether TOTP is
  confirmed for the stored session, and if not, calls the new
  `GET /auth/totp/setup-info` to re-fetch the secret/QR and route back to
  `TotpSetupScreen` — recovering even a fully killed-and-reopened app, not
  just a backgrounded one.

## 16. Device management + a real token-revocation bug fix

**Decision:** added a Devices screen (Settings) listing every device across
BOTH spouses -- with a husband/wife badge per card, so it's clear whose
phone is whose -- with a delete/revoke action. Either spouse can revoke
any device (lost/stolen phone, shared-trust model consistent with the
rest of the app); a revoked device must re-do the full setup-code flow to
get back in, it cannot just log in again.

While building this, found that revocation couldn't have worked at all:
`create_refresh_token()` already had a `device_id` claim, but every call
site passed a throwaway `uuid.uuid4()` instead of the actual `Device.id`
(the Device row didn't exist yet when the token was minted), and
`/auth/refresh` never checked the Devices table in the first place. Fixed
both: the Device row is now created and flushed *before* its refresh
token is minted (so the token embeds the real id), and `/auth/refresh`
now 401s if that Device row no longer exists.

**Consequence:** this invalidates refresh tokens minted before this fix
(their embedded device_id was random, matches nothing) -- any
already-logged-in session will need to log in again (password + TOTP)
the next time its 15-minute access token expires and it tries to refresh.
Necessary and safe -- no data loss, just a re-login.

## 17. Repo layout

**Decision:** Monorepo at the project root:
- `/backend` — FastAPI backend, admin panel, Docker Compose, install script
- `/mobile_app` — Flutter app
- `project.md` — source spec
- `DECISIONS.md` — this file

## 20. Stable device_uuid so repeated logins don't pile up duplicate devices

**Problem:** found in the field: the Devices screen showed three separate
"this phone" entries for what was genuinely a single physical phone,
minutes apart. Root cause: `_issue_full_login` (and `claim_role`)
unconditionally inserted a brand-new `Device` row on every successful
login, with nothing tying a login attempt back to a specific physical
installation -- every password+TOTP(+face) round trip, even from the
exact same app instance, was treated as an unrelated device. Testing
flows (like the new Add Device pairing feature) or anything causing a
re-login (token issues, logout/login cycles) made this worse.

**Decision:** the app now generates a random UUID once per installation
and keeps it in `SharedPreferences` (`DeviceIdentityService`) --
deliberately *not* `flutter_secure_storage`, so it survives
`SecureStorageService.clearAll()` (logout, revoked-device) and still
identifies "this same phone" across logout/login cycles. It resets only
on an actual uninstall, same boundary as every other local app datum
(consistent with #12's `allowBackup=false` decision to never let device
identity survive an OS-level transfer).

This `device_uuid` rides along on `/auth/setup/claim` and
`/auth/login/password`, then through the TOTP/face challenge JWTs (so
it's available wherever `_issue_full_login` finally mints tokens).
Server-side, `_issue_full_login` now looks up an existing `Device` row
for `(spouse_id, device_uuid)` first and reuses it (updates
`device_name`/`last_seen_at`/`refresh_token_hash`, keeps the same id)
instead of inserting a new one; a genuinely different `device_uuid` (a
real second phone) still gets its own row as before. Requests with no
`device_uuid` (old app builds) fall back to the previous always-insert
behavior unchanged.

Schema: `devices.device_uuid` (nullable) was added via an idempotent
`ALTER TABLE devices ADD COLUMN IF NOT EXISTS device_uuid VARCHAR(64)`
run at startup in `init_models()` -- since `Base.metadata.create_all()`
never alters existing tables (#2), this pattern is how additive schema
tweaks now ship without requiring a full database reset on every
release, unlike the breaking change in #13.

## 21. TOTP moved from per-spouse to per-device

**Request:** the product owner asked that the password stay a single
shared secret per role (whoever sets it first, it applies everywhere for
that role), but the authenticator (TOTP) code be set up independently on
each device -- i.e. adding a second phone for the same role (via #19's
pairing) should NOT just inherit the first phone's authenticator entry;
it should get its own.

**Decision:** `totp_secret`/`totp_confirmed` moved from `Spouse` to
`Device`. Password verification is unchanged (still checked against
`Spouse.password_hash`, shared). `/auth/login/password` now looks up the
calling device (by `device_uuid`, #20) after the password checks out:
- Device found and its TOTP already confirmed -> `mode: "verify"`
  (unchanged flow: `/auth/login/totp` against that device's own secret).
- Device not found, or found but never confirmed -> `mode: "setup"`: a
  fresh (or resumed-pending) TOTP secret for THIS device is returned, and
  a new `POST /auth/login/totp-setup-confirm` endpoint confirms it and
  finishes login, mirroring `/auth/totp/setup-confirm` (used for the very
  first device at claim time, which still works unchanged, just reading
  `device.totp_secret` instead of the spouse's now).

This composes directly with #19's pairing feature: a newly-paired device
naturally lands in `mode: "setup"` on its first login (new `device_uuid`,
no confirmed TOTP yet) and is walked through its own QR/authenticator
setup before finishing login -- exactly the requested behavior, no
special-casing needed between "pairing" and "any other new device".

Access tokens now embed `device_id` (needed so `/auth/me` and
`/auth/totp/setup-info|setup-confirm` know which device's TOTP state
they're reading/writing). Password reset (`/auth/password-reset/verify`)
no longer has one spouse-level secret to check against -- it accepts a
code from *any* of that spouse's confirmed devices, since the reset flow
doesn't know in advance which device the person is holding.

**Migration:** `devices.totp_secret`/`totp_confirmed` were added via the
same idempotent `ALTER ... ADD COLUMN IF NOT EXISTS` pattern as #20. For
deployments that still have the old `spouses.totp_secret`/`totp_confirmed`
columns, `init_models()` runs a one-time backfill copying each spouse's
secret onto every one of their existing Device rows (`WHERE
device.totp_secret IS NULL`) -- so already-working phones keep their
existing authenticator entry working, instead of every current user
being forced to redo TOTP setup after this update. Verified both the
backfill and the new-device "setup vs verify" branching against a local
Postgres.

## 22. Persistent, reusable admin setup code

**Request:** the admin panel's setup code was single-use per role and got
auto-deleted once both roles claimed -- generate it, and if you didn't
immediately use/save it, it was gone. The product owner asked for it to
be persistent (securely stored, reusable any time, for any device),
deletable/regeneratable on demand, and to make reinstalling the app on
the same device and setting up again with the same code "just work."

**Decision:** `SetupCode` is no longer single-use or auto-deleted --
`claim_role` dropped its `expires_at`/`claimed_husband`/`claimed_wife`
gating entirely; the only real gate left is "does this role already have
a Spouse row" (unchanged, and correctly so -- claiming can never silently
reset an existing password). `GET /admin/api/setup-codes/current` lets
the admin panel re-display the same QR/text on every page load;
`POST /admin/api/setup-codes` is idempotent (returns the existing code
instead of creating a duplicate); `DELETE .../setup-codes/{token}` lets
the admin rotate the shareable token on demand.

**Critical subtlety:** the Vault Master Key must NEVER change once
devices have claimed with it (they all need the SAME key to decrypt each
other's content) -- but the old design generated a fresh random VMK on
*every* code creation. Fixed by moving the VMK into its own singleton
`VaultKey` table, generated exactly once and always reused by every
SetupCode row from then on, so regenerating/rotating the shareable token
never touches the actual encryption key. A migration in `init_models()`
backfills `VaultKey` from any still-live `SetupCode.vmk_encrypted` (for a
deployment mid-setup, one role claimed) -- but a deployment that already
had BOTH roles claimed *before* this update has no recoverable key here,
since the old code was already hard-deleted; the admin panel shows an
explicit warning in that case (both roles registered, no current code)
that generating a fresh code now would produce a key incompatible with
already-claimed devices, and to use the in-app "Add Device" (#19)
pairing instead, which correctly carries the real in-memory VMK from an
already-authenticated device.

The app itself pivots gracefully when a code is used for an
already-claimed role: `ClaimRoleScreen` catches the 409
"already registered" response and calls `SessionProvider.beginPairing`
with the role+VMK it already has, landing on a normal login screen
instead of a dead-end error -- so reinstalling the same phone (or
sharing the one persistent code with a phone that already has that role)
"just works," per the request. Verified against a local Postgres:
idempotent creation, non-consumption on claim, matching VMK across
husband/wife claims and across token regeneration.

## 23. Security self-review: CORS lockdown + login rate limiting

**Context:** asked directly how secure this app is; a self-review (not a
substitute for an independent professional audit, but the closest
available given no third party has looked at this code) turned up two
real gaps, fixed here.

1. **CORS wildcard + credentialed admin cookie.** `cors_origins` defaulted
   to `"*"`, and Starlette's `CORSMiddleware` reflects the request's actual
   `Origin` back (rather than a literal `*`) whenever `allow_credentials=True`
   is set -- which the admin panel needs, since it authenticates via an
   httponly cookie. Combined, this meant ANY website could make
   cookie-authenticated requests to `/admin/api/*` if the admin ever had
   an active session and visited that site (classic CSRF-via-permissive-CORS).
   Fixed: `cors_origin_list` now defaults to the deployment's own
   `https://{domain}` and treats a literal `"*"` in `.env` as "not set"
   rather than honoring it -- this self-heals already-deployed `.env`
   files with the old default without requiring a manual edit.

2. **No rate limiting on auth endpoints.** Password/TOTP/face login,
   admin login, and password-reset verification had no attempt limit --
   password guessing in particular had nothing slowing it down (TOTP's
   own 6-digit space is impractical to brute-force inside one 30s window
   over a network, but defense-in-depth is still worth having). Added an
   in-memory, per-process sliding-window limiter
   (`app/services/rate_limit.py`) -- safe to keep in-process since the
   backend runs as a single uvicorn worker/container (no Redis needed).
   10 attempts/5 min per IP on login endpoints, 10/10 min on admin login
   and password reset, 20/10 min on setup-code claiming.

Verified against a local Postgres: CORS wildcard self-heals to the
domain-scoped origin even with the old `.env` value; the rate limiter
blocks the 11th attempt within its window and different endpoints have
independent budgets.

**Still open** (not fixed, flagged honestly): no independent
professional security audit has been done on this codebase; the VPS's
own OS-level hardening (SSH config, firewall, unattended upgrades) was
never audited as part of this project; there is intentionally no backup
of vault content (server never retains the VMK, so a lost/corrupted VPS
disk means permanent data loss -- a deliberate security/durability
trade-off, not an oversight).

## 24. 1GB media uploads: nginx body-size limit, streaming, progress

**Problem:** video upload failed with a raw "status code 413" the app
couldn't explain specifically. Root cause: nginx defaults to a 1MB
`client_max_body_size`, and the generated reverse-proxy config
(`install.sh`, coexisting-with-an-existing-nginx path) never set it --
so nginx itself rejected anything over 1MB before the request even
reached the backend.

**Decision:** raised the ceiling to 1GB end to end, and fixed two
correctness issues surfaced while doing that:

- `install.sh`'s generated nginx template now sets
  `client_max_body_size 1024m` and generous `proxy_read_timeout` /
  `proxy_send_timeout` / `client_body_timeout` (600s) so a big transfer
  on a slow mobile connection doesn't get cut off. Deployments whose
  nginx config was already generated before this need the same lines
  added manually (documented for the current deployment).
- `MAX_UPLOAD_MB` default raised from 200 to 1024.
- The MinIO client (`minio-py`) is synchronous, and was being called
  directly inside `async def` route handlers -- a single big
  upload/download blocked the *entire* event loop for its whole
  duration, stalling every other request (chat, other users' API calls)
  meanwhile. All storage calls now run via `run_in_threadpool`.
- Upload now streams straight from the spooled `UploadFile.file` into
  MinIO instead of first reading it into a Python `bytes` object --
  avoids doubling peak backend memory on large files.
- The app's Dio client used a blanket 20s/30s timeout tuned for quick
  API calls, which would abort a large, healthy upload/download in
  progress; media transfer calls now use their own generous (30 min)
  timeout instead of raising the global default.
- Added upload progress (`onSendProgress` -> a progress bar with %) on
  the vault create-entry screen, the one place users pick large video
  files.

**Known remaining limitation, accepted for now:** the app still
encrypts the whole file in memory client-side before upload (reads the
picked file fully into a `Uint8List`, then produces a same-size
encrypted copy) -- AES-GCM's usual single-tag construction isn't
naturally chunk-streamable without a framing scheme (e.g. STREAM), which
would be a much larger change. On a modern phone (4GB+ RAM) a 1GB video
should be fine; on very low-RAM devices it could still OOM. Not fixed
here; flagged as a follow-up if it turns out to matter in practice.

## 25. Home feed unified; wishlist de-task-ified with categories

**Decision:** Home replaced its multi-select-per-content-type tabs with a
single mixed feed (text/photo/video interleaved, newest first) plus a
multi-select filter bar (content type AND author, any combination,
always at least one of each group active) -- fetches all entries once
and filters client-side, so toggling filters is instant. Creating a new
entry now goes through a bottom sheet asking which type first, since
there's no longer a "current tab" to infer it from.

Wishlist changed from a checkbox/strikethrough task list to a plain
list -- no fulfilled-toggle interaction in the UI anymore (the backend
`is_fulfilled` field and endpoint are untouched, just unused from the
app; removing an item once you have it is what the existing delete
button is for). Wishlist items can now optionally have a category,
create-on-the-fly, reusing the exact same category mechanism vault
entries already had (`Category.scope` already supported `"wishlist"`
server-side -- this was already wired up in the API and the Flutter
service layer, just never exposed in the wishlist UI).

The vault create-entry screen was translated to Bengali (it was the one
onboarding-adjacent screen still fully in English) while touching it for
the wishlist-adjacent category work; its category picker already worked
identically for every content type and either spouse's uploads (no
role-based restriction existed) -- if "select History vs Husband
category" meant something more specific than "category selection should
just work everywhere," flag it and it'll get refined.

## 26. "Favorite Lines" discoverability

**Problem:** the user built (with me) a feature for writing intimate
lines to each other with separate husband→wife / wife→husband tabs and
a 5-star rating from each spouse -- this already existed
(`phrases_screen.dart`, backed by `PhraseModel`/`phrase_service.dart`,
per project.md and DECISIONS.md #5's "Favorite Lines" toggle) but was
only reachable via a small unlabeled heart icon among three crowded
icons in the Profile app bar. The user searched for it and couldn't
find it, despite it being fully built and working.

**Decision:** added a prominent, labeled card ("আমাদের প্রিয় লাইন") in
the Profile screen body, right where Wishlist already gets similar
visual weight, so the feature is findable by scrolling rather than only
by noticing a bare icon. Also translated the whole screen to Bengali
(it was the last major screen still fully in English) -- title, tabs,
add-line dialog, empty state, sort tooltip. No functional changes; the
tabs + per-spouse rating already worked exactly as originally requested.

## 27. Authenticator (TOTP) removed; password + biometric, hourly window

**Request:** the mandatory-TOTP model (DECISIONS.md #13, #21) was found
not to work well in practice -- too much friction for a two-person
private app. Replacement, exactly as specified: password required once
an hour; a fingerprint (device biometric) covers every app entry in
between, for that whole hour, regardless of how many times the app is
backgrounded/reopened. No authenticator/TOTP anywhere anymore.

**Decision:**
- **Server side**, password is now the only server-verified factor.
  `/auth/login/password` issues real tokens directly (or a face
  challenge first, for spouses who opted into that separate optional
  step) instead of returning a TOTP challenge/setup token.
  `/auth/setup/claim` no longer generates a TOTP secret. The
  `/auth/totp/*` and `/auth/login/totp*` endpoints are gone.
  `Device.totp_secret`/`totp_confirmed` columns are left in place, just
  unused, rather than dropped (avoids yet another destructive
  migration).
- **Client side**, a successful password login also records a local
  `lastPasswordAuthAt` timestamp (secure storage). Every re-entry point
  -- cold start, resuming from background, or the idle auto-lock timer
  firing -- checks the elapsed time: under an hour gets
  `SessionState.needsBiometric` (a fingerprint/face/device-PIN OS prompt
  via `local_auth`, `biometricOnly: false` so a phone with no biometric
  hardware still has a fallback), an hour or more gets `locked` (the
  password screen again). Biometric unlock is **purely local** -- it
  never calls the server at all, since the tokens are already valid in
  secure storage from the last real login (and the existing Dio
  refresh-token interceptor transparently renews an expired 15-minute
  access token on the next API call regardless). It does NOT reset the
  hourly clock; only a real password entry does.
- `MainActivity` changed from `FlutterActivity` to
  `FlutterFragmentActivity` (`local_auth`'s biometric prompt needs a
  FragmentActivity host), and `USE_BIOMETRIC` was added to the manifest.
- **Password reset** could no longer ask for a TOTP code from each
  spouse (DECISIONS.md #13's original dual-verification design). It's
  now: an already-authenticated device (either spouse's, or the same
  person's other paired device -- matching the app's existing
  full-mutual-trust model) approves the reset by pasting its code into
  a new Settings screen and tapping Approve, no code entry required on
  their end beyond that. The locked/forgotten-password device polls
  `/auth/password-reset/status` every few seconds (no push
  notifications involved -- those don't work yet regardless, see the
  code-review findings) and reveals the new-password field once
  approved. Only one approval is required now, not both spouses.

Verified against a local Postgres: claim and login both issue tokens
directly with no TOTP step or fields in the response; two different
devices sharing the same role's password both log straight in with no
per-device setup; the old TOTP endpoints 404; the new approve/status/
complete password-reset sequence works end-to-end and rejects
completion before approval.

## 28. Chat read receipts, voice playback, media zoom; Reel aspect ratio

**Chat gaps closed:**
- **Seen ticks.** `POST /chat/messages/{id}/read` already existed and
  already set `read_at`, but nothing in the app ever called it, and it
  never told the sender. Now the chat screen marks every incoming
  message read as soon as it's loaded or arrives over the socket (the
  screen being open means it's being looked at), the endpoint broadcasts
  a new `chat_read` WS event to the sender, and sent messages show a
  WhatsApp-style tick: single grey (sent), double grey (delivered),
  double blue (seen). While in `ws_manager.send_to_spouse` for this,
  fixed a real bug found during the code review pass: it returned `True`
  (marking a message delivered) whenever the connection set was merely
  non-empty, even if every individual `send_text` call had thrown --
  now it only returns `True` if at least one send actually succeeded.
- **Voice messages were unplayable** -- content_type "voice" just showed
  a `[voice]` text placeholder. New `DecryptedVoicePlayer` (audioplayers'
  `BytesSource`, no temp file needed) with play/pause and a position/
  duration readout.
- **No way to see media full-size.** Tapping a photo/video bubble now
  opens a full-screen `MediaViewerScreen` -- pinch-zoomable for photos,
  full aspect-ratio video playback -- instead of only ever seeing the
  small in-bubble preview.

**Reel aspect-ratio distortion, root cause:** `Stack(fit:
StackFit.expand)` gives every non-positioned child a *tight* box
matching the full screen. `Image`'s own `fit` parameter (BoxFit.cover/
contain/etc.) works fine under tight constraints -- it paints correctly
within whatever box it's given -- but `AspectRatio` is a *layout* widget
that needs actual freedom to size itself; under fully tight constraints
it has no choice but to obey the box exactly, ignoring its ratio. That's
why video stretched/cropped wrong while nothing else did. Fix: video is
now wrapped in `Center(child: SizedBox(width: screenWidth, ...))` --
width fixed to the screen, height computed from the real aspect ratio
via the loosened constraints Center provides; images use
`DecryptedFullImage`'s new `fit: BoxFit.fitWidth`, which needs no such
wrapper since BoxFit works at paint time. Both now show correctly
letterboxed/pillarboxed on the full-bleed black background rather than
stretched -- landscape video displays as landscape, not warped to fill
a portrait screen. `DecryptedFullImage` gained a `fit` (default
`BoxFit.contain`, used for the new zoom viewer and now also fixes the
previously-unspecified, effectively-undefined fit in the vault
entry-detail screen) and `zoomable` param, with `BoxFit.cover` used at
the small fixed-size preview call sites (chat bubbles).

Verified against a local Postgres: a message's `read_at` is null until
the recipient marks it, marking works and persists, and a sender
marking their own message is a safe no-op.

## 29. Chat: sounds, WhatsApp-style voice recording, privacy mask

**Sounds:** chat was completely silent -- easy to miss a new message
while the screen was open but not focused on the conversation. Added
two short, distinct sounds (synthesized locally as plain sine-tone WAVs,
no external asset library needed) played via `audioplayers`: a light
upward blip on send, a two-note "ding-dong" on receiving a genuinely new
incoming message (not on `chat_ack` echoes of your own sends, not on
`chat_read` events).

**Voice recording redesigned, WhatsApp-style:** previously tapping the
mic just silently recorded with zero feedback. Now, while recording, the
input row is replaced with: a live waveform (bars driven by
`record`'s `onAmplitudeChanged` stream, so it visibly reacts to actual
volume), a running MM:SS timer, a delete/cancel button, a pause/resume
button (the `record` package supports pausing and resuming into the
*same* file, confirmed via its source before relying on it), and a send
button that stops recording and sends immediately in one tap.

**Privacy mask (the eye icon):** a new app-bar toggle in the chat screen
that replaces every message's content with a starred placeholder
(`🔒 ★ ★ ★ ★`) -- deliberately **local UI state only**, not persisted,
not synced, and not visible to or affected by the other spouse's device
at all. It exists purely so whoever is holding a specific phone can
instantly hide the transcript from anyone glancing at that screen
(including re-hiding it from themselves if handing the phone to someone
else); the other spouse's own chat view is completely unaffected unless
they independently toggle their own icon.

## 30. Push notifications made fully functional (real FCM credentials)

**Problem:** `notify_spouse()` always sent a WebSocket ping (works only
while the app is open) and *attempted* a Firebase push for the
background/killed-app case, but `send_generic_push()` was calling
`credentials.Certificate({})` -- an empty dict, not a real key -- so it
silently failed every time. There was also no Flutter-side Firebase
integration at all (no `firebase_core`/`firebase_messaging` packages, no
`google-services.json`, nothing calling the already-existing
`ProfileService.updatePushToken()`), so even a working backend would have
had no token to send to.

**Fixed, backend:** the user provided a real `google-services.json`
(Android app config, not a secret -- committed to
`mobile_app/android/app/`) and a real Firebase Admin service-account key
(a genuine secret). The service-account JSON is stored ONLY at
`backend/firebase-service-account.json`, gitignored, never committed, and
mounted read-only into the backend container by `docker-compose.yml`; its
container path is read from a new `FCM_SERVICE_ACCOUNT_PATH` setting
(replacing the old, never-actually-usable `fcm_server_key`/
`fcm_project_id` fields, which needed a legacy server-key model
`firebase-admin` doesn't use). `_firebase()` lazily initializes the
Admin SDK once from that file and caches the failure so a missing/invalid
key degrades to "pushes silently skipped" rather than raising on every
request that would otherwise trigger one. `messaging.send()` is a
blocking call, so it's offloaded via `run_in_threadpool` (same pattern as
the MinIO calls in `storage.py`) to avoid stalling the event loop.

**Fixed, backend, privacy constraint:** the user was explicit that a push
must never reveal anything from inside the app -- no message text, no
names -- only a generic, category-level phrase ("a text/photo/video
message arrived"). `notify_spouse()` gained an optional `content_type`
param (the chat message's or vault entry's own already-generic kind:
text/photo/video/voice) and a `_NOTIFICATION_TEXT` lookup table picks one
of a small set of pre-written Bengali phrases from `category` +
`content_type` -- never anything derived from the actual encrypted
payload. Every `notify_spouse(...)` call site (`chat.py`, `content.py`,
`social.py`, `phrase.py`) was audited; `chat` and `content_new` now pass
their content_type through, everything else (reaction/comment/
consent_request/consent_resolved/phrase) uses a fixed category-level
phrase since there's nothing further to safely differentiate.

**Fixed in passing, `PUT /device/push-token`:** this endpoint updated
whichever of the calling spouse's device rows was most recently
*created*, not the device the request actually came from -- harmless
while nothing real depended on it, but silently wrong (and now directly
user-facing) once tokens started actually being registered. Switched to
`get_current_spouse_and_device`, which resolves the calling device from
the access token's own `device_id` claim (same mechanism already used
elsewhere for per-device state).

**Flutter side:** added `firebase_core`/`firebase_messaging`, applied the
`com.google.gms.google-services` Gradle plugin (Android-only integration
-- no `firebase_options.dart`/FlutterFire CLI needed since the native
`google-services.json` already supplies everything `Firebase.
initializeApp()` needs on Android). `PushNotificationService.registerToken()`
requests the OS notification permission and calls the existing
`ProfileService.updatePushToken()`; it's invoked from every real
authentication completion point in `SessionProvider` (fresh claim, fresh
login, completed pairing) -- deliberately NOT from the biometric-unlock
path, since that reuses an already-valid session and the token-refresh
listener (`FirebaseMessaging.instance.onTokenRefresh`) already covers
token rotation independently of login events. The background message
handler is intentionally a no-op: every push is sent as a plain FCM
"notification" message, which Android already renders in the system tray
on its own with zero app code running; FCM just needs *something*
registered to wake for. All of this only ever supplements the WebSocket
channel, which still handles every foreground/open-app update exactly as
before.

**Verified:** `_firebase()` initializes successfully against the real
service-account file (`project_id: parsonal-40d40` echoed back),
`_notification_body()` produces the correct fully-generic Bengali text
for every category/content_type combination with no content leakage,
`flutter analyze` is clean, and a release APK built successfully with the
Google Services plugin wired in. Actual end-to-end push delivery to a
physical device could not be verified in this environment (no real device
token available here) -- that's confirmed by the user field-testing the
shipped APK.

## 31. Iconsax icons, Kohinoor font, real video thumbnails/trim/controls, chat pagination+search

**Icons -- `iconsax` -> `iconsax_flutter`:** the user asked for the whole
app's icon set to switch to "iconsax". The actual `iconsax` package on
pub.dev is 5 years stale and its identifiers are exactly mirrored by
`iconsax_flutter` (1.0.1, `Iconsax.xxx` naming, actively published more
recently), so that's what got used -- same visual icon set, a build that
won't silently rot. All 64 unique `Icons.*` identifiers used across
`lib/` were mapped one-for-one to `Iconsax` equivalents (verified against
the package's actual generated icon-name list, not guessed) and replaced
mechanically across every file; `flutter analyze` stayed clean throughout.
A few icons have no exact Iconsax equivalent (`Icons.face` for the face-
verification screen, `Icons.done_all` for the double read-receipt tick) --
mapped to the closest semantic match (`scan`, `tick_circle_copy`) rather
than left as Material icons, so the icon set is now fully consistent.

**Font -- Kohinoor:** copied from the path the user gave
(`aybay-user/assets/fonts/`) into `mobile_app/assets/fonts/`, registered
as a 4-weight family in `pubspec.yaml`, and set as `ThemeData.fontFamily`
+ applied across the base `TextTheme` in `app_theme.dart`. Kohinoor is
Apple's Bengali system typeface, which fits well since virtually all of
this app's UI text is Bengali.

**Video thumbnails actually generate now:** previously nothing ever
called the backend's already-supported optional `thumbnail` upload field
for videos, so every video in the vault feed/Reel/chat rendered as an
identical blank placeholder with a play icon -- impossible to tell which
video was which without opening each one (this was open code-review
finding #3). `video_thumbnail` (the obvious pub.dev package) turned out
to ship an Android Gradle config that still calls the long-removed
`jcenter()` repository and fails outright under this project's AGP 9
toolchain; swapped for `get_thumbnail_video`, which exposes the identical
`VideoThumbnail.thumbnailData()` API and builds cleanly (also happens to
already be a transitive dependency of `video_trimmer` below). A thumbnail
is now generated client-side on every video upload (vault entries, chat)
and uploaded alongside the video; chat bubbles previously hard-coded
`hasThumbnail: false` even when one existed, so `ChatMessageOut` gained a
`media_has_thumbnail` field to fix that too.

**Video player: real controls + trim/clip:** `DecryptedVideoPlayer` had
only a bare play/pause toggle; added a scrub bar (position/duration) and
±10s skip buttons -- standard playback controls, matching what the user
asked for. For "clip a video," added an optional scissor button that
opens a new `VideoTrimScreen` built on `video_trimmer` 5.x, which trims
natively on-device (no FFmpeg -- `ffmpeg_kit_flutter`, which most older
trim tutorials rely on, was pulled from pub.dev entirely in 2025 when the
FFmpegKit project was archived). Trimming is **non-destructive**: the
picked range is exported, re-encrypted, and uploaded as a **brand-new**
video entry; the original is never touched, so a bad trim never risks
losing the source clip. Wired into both the vault entry detail screen and
Reel (both browse the same video entries) via a shared
`handleVideoTrimRequested()` helper.

**Chat: real pagination + date dividers.** `GET /chat/messages` accepted
a `before` query param but the query never actually applied it -- every
"next page" silently re-fetched the same newest 50 messages. Fixed to
filter by the anchor message's `created_at`. Client-side, replaced the
plain `ListView.builder`/`ScrollController` with
`ScrollablePositionedList` (`ItemScrollController` +
`ItemPositionsListener`) specifically because it supports jumping to an
arbitrary item index in a lazily-built list without needing every item
between built first -- needed both for (a) keeping the visual scroll
position stable when older messages are prepended above what's on screen
(jump to `index: addedCount` right after prepending) and (b) jumping
straight to an arbitrary search result somewhere in a long, mostly-
unloaded history (below). A centered date-pill divider (আজ / গতকাল / the
date) is inserted wherever two consecutive messages fall on different
local days.

**Chat: search.** Since chat content is E2E encrypted, the server never
sees plaintext and genuinely cannot search it -- this has to happen
entirely on-device against already-decrypted messages. Typing a query and
submitting first checks whatever's currently loaded; if nothing matches
and more history exists, it keeps auto-paging further back (100 messages
at a time, capped at 40 pages as a sane worst-case backstop) until either
a match turns up or the very start of the conversation is reached,
merging each page into the same message list the main view scrolls
through. Tapping a result jumps the chat view straight to that message
via `ItemScrollController.scrollTo(index:)`.

**Verified:** `flutter analyze` clean throughout every step above, and a
release APK built successfully with `video_trimmer`'s native trim plugin,
the Iconsax font, and Kohinoor all packaged in.

## 32. Video thumbnail self-heal, edit/delete everywhere, --split-per-abi builds

**Video thumbnails still weren't showing.** #31's fix only generates a
thumbnail at *upload* time -- every video already in the vault from
before that change (or any where on-device generation had silently
thrown, since there's no way to see a phone's logs from here) still had
no thumbnail and rendered as an identical blank box, exactly what the
user was still seeing. Rather than a one-off migration script,
`DecryptedThumbnail` now self-heals: given a video asset with no
thumbnail, it downloads the video once, generates a thumbnail on-device,
uploads it via a new `PUT /media/{asset_id}/thumbnail` endpoint (so
every later view of that asset is instant, server-side thumbnail and
all), and displays it immediately -- no visible difference to the user
beyond "it just works now," self-healing the first time anyone actually
looks at each old video. `vault_entry_card.dart` also stopped skipping
`DecryptedThumbnail` entirely for thumbnail-less videos (it used to fall
straight to a flat placeholder box without even trying).

**Edit + delete, everywhere content gets added:** audited every place
the app lets a spouse add something and checked whether removing/
changing it afterward actually worked:
- **Vault entries** already had this (consent-based edit/delete,
  requiring the other spouse's approval, per the original spec) -- no
  change needed.
- **Wishlist items** already had a working `PATCH` endpoint for editing
  server-side; it was just never called from the UI, which only exposed
  delete. Added an edit button reusing the existing add-item dialog in
  edit mode.
- **Phrases ("favorite lines")** had a working `DELETE` endpoint that
  was, again, never wired to any UI control. Added an edit endpoint
  (author-only, matches the existing delete's author check) and wired
  both into the phrase card via a menu. Editing a phrase's text clears
  its existing ratings -- they were given for the old wording and would
  misleadingly carry over otherwise.
- **Comments** had neither edit nor delete anywhere, client or server.
  Added both (author-only), including cleaning up any heart reactions on
  a deleted comment, which have no DB-level cascade (reactions are
  polymorphic -- `target_type`/`target_id`, not a real foreign key).

All of the above follow the same **immediate, author/owner-only**
pattern already established by wishlist's delete -- no consent/approval
step, unlike vault entries, since these are lower-stakes than vault
content, which already has its own (unchanged) consent flow. Category
edit/delete was left out of this pass (organizational metadata, not
"content" in the sense the request was about) -- worth a follow-up if
actually wanted.

**APK size: always build `--split-per-abi` from now on.** The user asked
why the APK had crossed 100MB; breaking down the archive by file size
showed ~88% of it was native `.so` libraries -- and specifically, the
*same* libraries (Flutter's own engine, the compiled Dart app code,
Google ML Kit's face-detection and barcode-scanning native libraries)
duplicated three times over, once per CPU architecture (`arm64-v8a`,
`armeabi-v7a`, `x86_64`), because a plain `flutter build apk --release`
bundles all of them into one "fat" universal APK. Since this app is
sideloaded (never distributed through the Play Store, which would
otherwise handle per-device delivery automatically via an .aab), that
tripling is pure waste for literally every real installer -- any actual
phone only ever uses one architecture (`arm64-v8a` for anything from the
last several years). Switched to `flutter build apk --release
--split-per-abi`, which produces three separate APKs instead of one; the
`arm64-v8a` one dropped from ~105MB to ~40MB. This is now the **standing
build method** for every future release of this app (saved to memory,
not just this file) -- README.md's build section and every future
release/USER_GUIDE.md link should use the `arm64-v8a` split artifact.

## 33. Home feed redesign, free-form reactions, no-consent vault edit/delete, Reel layout fix

**Vault entries: edit/delete no longer need spouse approval, for now.**
Explicit user instruction, applied the same way as wishlist/phrases/
comments already work: new `PUT`/`DELETE /vault/entries/{id}` apply
immediately (still notifying the other spouse, generically, same as any
other change). The older request/consent endpoints
(`edit-request`/`delete-request`/`consent-requests`) are left in place
on the backend but the client no longer calls them -- easy to revert to
if the couple wants approval back later, without losing any code.

**Reactions, reworked to match what was actually asked for the first
time.** The old `ReactionBar` showed a small fixed set of 6 preset emoji
in a long-press bottom sheet. That was never the ask: the user wants to
tap an "add emoji" button and have their *phone's own keyboard* emoji
panel open, so literally any emoji is available, repeatable -- add
several different ones in a row without the sheet closing between each.
Turns out the backend already supported this shape exactly (the
`uq_reaction` unique constraint is per `(target, spouse, emoji)`, not
per `(target, spouse)` -- multiple *different* emoji from the same
person were always allowed, just never exposed by the UI). Replaced the
preset picker with a bottom sheet holding one focused, empty `TextField`
-- tapping it brings up the normal keyboard, whose own emoji key (e.g.
Gboard's smiley icon) is how the user actually picks the emoji; hitting
the checkmark or Enter submits it as a new reaction and immediately
clears the field for the next one, so "add a bunch of different emoji in
one sitting" is a fluid loop rather than repeated dialog reopens.

**Vault entry cards, redesigned.** Removed the husband/wife avatar+label
from the card header -- purely redundant now that the husband/wife
filter pills exist specifically to separate that content, showing it a
second time on every single card added nothing. New header is just the
timestamp + a three-dot menu (favorite / edit / delete, all immediate,
per above). The reaction bar now sits directly under the media, before
the caption text -- previously reactions weren't shown on cards at all,
only in the detail view.

**Home screen: nothing stays pinned while scrolling.** Previously the
app bar was a normal fixed `AppBar` with the countdown card and filter
pills below it in a plain `Column`, permanently glued to the top.
Rebuilt around `CustomScrollView` with the app bar, countdown card, and
filter row *all* packed into one `SliverAppBar`'s `bottom:` slot, with
`floating: true, snap: true` -- the whole header now slides away
together on scroll-down and snaps back on the very next scroll-up
gesture (not needing a scroll all the way back to the top). App bar
title is now "পার্সোনাল" with a small leading icon, replacing the
placeholder English "Our Vault". Filter pills also got a much thinner
selected-state border (was 1.5px, now 0.75px) and switched from a
`Wrap` (which pushed overflow to a second line) to a horizontally-
scrolling row, so a growing category list scrolls sideways instead of
growing the header's height.

**Video clip/trim feature removed entirely** (was added last release;
explicitly not wanted) -- deleted `video_trim_screen.dart` and
`video_clip_helper.dart`, dropped the `video_trimmer` package (and its
transitive deps: `flutter_native_video_trimmer`, `archive`, `image`,
`posix`, `transparent_image` -- a nice side-effect trim on APK size too),
and removed the scissor button + `onTrimRequested` plumbing from
`DecryptedVideoPlayer`, the entry detail screen, and Reel. Real playback
controls (scrub bar, ±10s skip) from the same release stay -- only the
trim/clip capability itself is gone.

**Reel: fixed overlapping action icons.** The comment button (bottom
overlay, pinned near the right edge) and the favorites-only toggle (a
separately-positioned `FloatingActionButton`, default bottom-right) sat
on top of each other in the same corner. Removed the FAB; both actions
now live in one clean vertical column on the right side (Instagram-
style) -- favorites-toggle above, comment below -- with the caption/
reaction area on the left given a fixed right margin so it never reaches
into that column's space.

**Verified:** `flutter analyze` clean (no errors or warnings, only the
same pre-existing style infos as before), backend imports cleanly with
all new routes registered, and a `--split-per-abi` release build
succeeded (`arm64-v8a` ~40MB, unchanged despite the net-new features --
video_trimmer's removal offset the added code).

## 34. Real profile identity everywhere, per-person reactions, notification inbox, chat gallery

**Profiles: either spouse can edit either one now.** Previously `PUT
/profile/me` only ever touched the *caller's own* profile, and the
Flutter UI hid the edit controls entirely when viewing the other
person's tab. New `PUT /profile/{role}` lets either spouse edit either
profile directly -- same shared-trust model as device management, vault
entries, etc. `/profile/me` is left in place, just no longer called by
the client.

**Real name + photo everywhere a role was shown generically.** Vault
entry cards, comments, and Reel used to show a plain "husband"/"wife"
label with a colored generic icon. New `ProfileCache` (fetches +
decrypts both profiles once per session, since there are only ever two)
backs a small `AuthorAvatar`/`AuthorRow` pair of widgets used everywhere
"who did this" needs to render -- falls back to the old generic
label/icon only if that profile has no name/photo set yet.

**Reactions, grouped by person instead of by emoji.** Now that reacting
with several different emoji is normal, showing a count next to each one
made no sense. `GET /reactions/...` now returns one row per person
(`{role, emojis: [...], is_me}`) instead of one row per emoji with
husband/wife counts -- the client renders one line per reactor: their
avatar, then all their emoji stuck directly together, no counts. Tapping
an emoji in your own row removes it.

**Notification inbox.** Notifications were purely ephemeral before --
a WebSocket ping that showed a SnackBar *if* you happened to be looking
right then, nothing persisted, no history, no unread count. New
`NotificationLog` table records every `notify_spouse()` event per
recipient (`notify_spouse()` now takes `db` and writes a row before
doing anything else); `GET /notifications`, `GET /notifications/unread-
count`, `POST /notifications/mark-all-read` back a bell icon (badge =
unread count, refreshes live off the same WS events the SnackBar system
already listens for) and a full inbox screen. Body text is rendered on
read from category/content_type via the same `notification_body()`
table pushes already used -- never stored pre-rendered, so a wording
change applies retroactively, and the same "never reveals actual
content" guarantee from the push-notification work holds here too.

**Home screen, further redesign on top of #33:**
- Long captions get a "আরও দেখুন" (see more) toggle instead of being cut
  off with no way to read the rest.
- Media no longer force-crops to a fixed 16:10 box -- `DecryptedThumbnail`
  gained an `onAspectRatio` callback (decodes real width/height once
  bytes arrive) that drives the card's `AspectRatio`, capped so height
  never exceeds 2x the width (an extreme portrait photo/video would
  otherwise blow out the feed's rhythm) but otherwise shows the media's
  true proportions.
- New category filter row (horizontal, "সব" selected by default) using
  the vault categories that were already being fetched for the create-
  entry flow but never surfaced as a filter.
- Split the single floating `SliverAppBar` from #33 into two: the title
  bar alone floats/snaps back on any scroll-up, while the countdown card
  + filter pills now live in a separate, non-floating sliver that
  scrolls away normally and only comes back once actually scrolled back
  near the top -- fixes the previous version snapping the *entire*
  header back on every small upward scroll jitter, which read as buggy.

**Tap-to-fullscreen-zoom, audited everywhere media shows.** Vault entry
cards, the entry detail screen's photo, and profile photos now all open
the same `MediaViewerScreen` (moved from `screens/chat/` to `widgets/`
since it's no longer chat-specific) on tap -- pinch-zoomable, aspect
ratio always preserved via `BoxFit.contain`. Chat bubbles already had
this from an earlier release.

**Chat media gallery.** New gallery icon in the chat app bar opens a
grid of every photo/video ever exchanged (`GET /chat/media`, joining
`MediaAsset` to `ChatMessage` by `chat_message_id`). Tapping a thumbnail
opens the same full-screen zoom viewer; each thumbnail also has a
"পোস্ট করুন" (post) button that publishes that exact image to the home
feed as a new vault entry -- reusing the already-uploaded `MediaAsset`
via the existing `media_asset_ids` param on `POST /vault/entries`
instead of re-uploading. A `MediaAsset` ending up linked to both a chat
message and a vault entry is fine: `entry_id` and `chat_message_id` are
independent nullable FK columns, and every query that lists media
already filters by exactly one of them.

**Bottom nav:** labels removed (`NavigationDestinationLabelBehavior.
alwaysHide`) -- icons alone, per explicit request.

**Verified:** `flutter analyze` clean, backend imports cleanly (80
routes registered), and a `--split-per-abi` release build succeeded
(`arm64-v8a` still ~40MB despite this being the largest single batch of
UI changes yet).

## 35. Home randomization, Bengali-only pass, "সব" filters, face verify fully off, countdown redesign, comment preview, intimate mode

**Home feed order is now shuffled on every load.** `_load()` calls
`entries.shuffle()` right after fetching, per explicit request -- a
fresh, non-chronological mix each time the screen opens or refreshes,
rather than the same newest-first order.

**Approval Request screen removed entirely.** It was already dead in
spirit once vault edit/delete and profile edits went no-consent (#33,
#34) -- `consent_requests_screen.dart` deleted, its app-bar entry point
and import removed from `home_tab.dart`. The old consent-request
endpoints stay on the backend, just unreferenced by the client.

**Face verification fully disabled, client AND server.** Previously
only "optional" -- now cut at the root: `login_password()` in
`backend/app/routers/auth.py` no longer branches on
`spouse.face_verification_enabled` at all and always issues a full
login (catches a real correctness risk: if only the client had stopped
checking `requires_face`, a spouse who'd left the old toggle on would
still get back a tokenless challenge response and crash). Client-side,
`SettingsScreen`'s toggle UI, `LoginScreen`'s branch, and their now-
unused imports are gone. To be rebuilt properly later, per the user.

**"সব" (All) pills, default-selected, on both home filter groups.** The
type filter (টেক্সট/ছবি/ভিডিও) and role filter (স্বামী/স্ত্রী) rows each
gained an explicit "সব" pill up front, selected whenever every option in
that group is already on -- tapping it calls a new `_selectAll()` helper
that fills the whole `Set` at once, rather than the previous "start with
everything on but no way to visibly represent or return to that state"
behavior.

**Countdown card redesigned to a standard digital-countdown look.** The
old single running line of text ("X days Y hours...") is now four
boxed digits (দিন/ঘণ্টা/মিনিট/সেকেন্ড) separated by colons, `_CountdownBoxes`
built from a small `_CountdownBox`/`_Colon` pair, with a leading
`Iconsax.profile_2user_copy` (two-people) icon per the user's specific
ask for something that visually reads as "the two of us coming
together."

**Home card action order + inline comment preview.** Per-card action row
is now emoji-add -> comment -> view count (was reversed before). New
`CommentPreview` widget shows up to the 2 most recent comments directly
under a post with no tap required (tapping the header still opens the
full thread), mirroring the pattern Reel already used.

**Quick-tap emoji suggestions alongside free keyboard entry.** The add-
emoji sheet now offers a `Wrap` of 8 common emoji for one-tap adding, on
top of the existing free-text field (native keyboard emoji picker) from
#33 -- typing to find an emoji on a phone keyboard is real friction for
the common cases, and this doesn't remove the ability to pick anything.

**"আমাদের প্রিয় লাইন" (Phrases) now requires a fresh fingerprint every
single entry**, independent of the app's normal hourly password/
biometric window. `BiometricService.authenticate()` gained an optional
`reason` string (still defaults to the normal unlock prompt everywhere
else); a new `openPhrasesScreen(context)` helper gates the push behind
its own `authenticate(reason: 'প্রিয় লাইন দেখতে যাচাই করুন')` call and both
places that used to push `PhrasesScreen()` directly now go through it.

**Bengali-only pass.** Beyond translating the leftover English strings
this turned up (a stray SnackBar in `entry_detail_screen.dart`, the
`[unable to decrypt]` fallback repeated across every service that
decrypts text, an `"It's a match!"` celebration overlay, `"💚 match"` on
Reel, a quoted English feature name in Settings, a `daily_reminder`
push fallback), the bigger fix was systemic: nothing in the app ever set
an Intl locale, so every `DateFormat` call (chat timestamps and date
dividers, the audit log, devices screen, notification list, search
results) was silently rendering English month names in Western digits
regardless of what the surrounding Bengali text said, and `showDatePicker`
/`showTimePicker`'s own chrome (CANCEL/OK, month grid) was English too
since no `MaterialApp.locale`/`supportedLocales` were set. Fixed at the
root instead of per-callsite: `flutter_localizations` added,
`initializeDateFormatting('bn', null)` + `Intl.defaultLocale = 'bn'` set
once in `main()` before `runApp`, and `MaterialApp` now pins
`locale: Locale('bn')` with `supportedLocales: [Locale('bn')]` and the
three `GlobalXLocalizations.delegate`s. Every existing unlocalized
`DateFormat.xxx()` call site picks this up automatically (Intl resolves
locale from `Intl.defaultLocale` when none is passed) -- no call site
needed touching.

**"Intimate mode" -- shared green/blue theme toggle.** New moon-icon
button in the chat app bar either spouse can tap to flip the *entire
app's* accent color from green to blue on **both** phones at once, as
an at-a-glance private signal ("we're talking about something just
between us right now"). Backed by the existing generic `AppSetting`
key/value table (key `intimate_mode_enabled`) rather than a new model;
`PUT /settings/{key}` now additionally broadcasts
`{type: "app_setting", key, value}` over the WS connection to *both*
spouse roles (not just "the other one," so a phone with more than one
open connection also stays in sync). `SessionProvider` owns the single
global listener for this (a WS event, not per-screen, since it's one
app-wide flag) plus `loadIntimateMode()`/`toggleIntimateMode()`;
`AppTheme.light()/dark()` take an `intimate` flag that swaps the
`ColorScheme.fromSeed` seed color, and `main.dart`'s `MaterialApp` is
now built inside a `Consumer<SessionProvider>` so the theme rebuild
propagates through Flutter's own `Theme` InheritedWidget mechanism --
every screen reading `Theme.of(context).colorScheme.primary` updates in
place, live, without losing any widget state (unlike keying/rebuilding
the whole subtree). About 20 widgets across chat, home, the countdown
card, comments, reactions, the reel match overlay, wishlist, and the
notification list were switched from the old hardcoded
`AppColors.halalGreen` constant to `Theme.of(context).colorScheme.
primary` for this to actually show up where it matters; a handful of
screens that can only ever be seen *before* a real login exists
(onboarding, login, biometric-unlock, password-reset approval) or that
belong to the already-disabled face-verification flow were deliberately
left on the static green constant, since intimate mode can never
logically be "on" there.

**Verified:** `flutter analyze` clean (only the same pre-existing
info-level lints), backend imports cleanly (80 routes registered), and
a `--split-per-abi` release build succeeded.

## 36. Fix intimate-mode green shift, single-line countdown, edge-to-edge feed, combined action row

Follow-up fixes from real-device feedback on #35's release.

**Green looked "off" even with intimate mode off -- fixed.**
`ColorScheme.fromSeed(seedColor: AppColors.halalGreen)` does NOT make
`scheme.primary` equal the seed hex -- Material 3's tonal-palette
algorithm computes its own (visibly more muted) tone-40 shade from the
seed. Every widget that used to read the hardcoded `AppColors.halalGreen`
constant directly got the *exact* original green; once #35 switched
those same widgets to `Theme.of(context).colorScheme.primary` (needed
for the intimate-mode toggle to actually retint them), they silently
picked up that different M3-computed shade instead -- a real,
unintended color shift the user immediately noticed. Fixed at the
source: `AppTheme.light()/dark()` now do
`ColorScheme.fromSeed(...).copyWith(primary: seed)`, pinning
`colorScheme.primary` to the exact chosen hex (green or, in intimate
mode, blue) regardless of what M3's tonal derivation would have picked.

**Bottom nav height reduced.** No labels are shown
(`alwaysHide`), so the default Material 3 height (80) was leaving
noticeably dead vertical space under a lone icon -- `NavigationBarTheme
Data.height` set to 58.

**Countdown card: single line, no colons, smaller boxes.** Redesigned
again -- icon, "কবে দেখা হবে", and the countdown itself (or the "tap to
set a date" / "practically here" fallback text) now all sit on one Row,
right-aligned inside a `FittedBox` so it always fits regardless of
screen width. The four day/hour/minute/second boxes lost their
in-between colon separators (the boxes read as distinct on their own)
and their separate unit-label-underneath -- each box now just shows
`"07দি"`, `"04ঘ"`, etc., number and unit abbreviation together, in a
much smaller box.

**Home feed: edge-to-edge, no card, thin divider.** `VaultEntryCard`
no longer wraps itself in a `Card` (which added rounded corners, a
background fill distinct from the scaffold, and per-card margins) --
now a plain full-width `Column`, so each post visually spans the entire
screen width like a normal social feed rather than sitting inside a
separate box. `home_tab.dart`'s `SliverPadding(all: 12)` wrapper is
gone; a thin 1px `Divider` (grey, 15% alpha) between posts does the
separating instead of card gaps. `favorites_screen.dart` and
`history_screen.dart` (same `VaultEntryCard`) got the matching
`ListView.separated` treatment for visual consistency.

**Post action row: side by side, not stacked.** The add-emoji button,
comment button, and view count used to be three separate stacked
blocks (each with its own leading icon/header). `ReactionBar` split
into `ReactionList` (just the reactor avatar+emoji rows) and
`ReactionAddButton` (just the icon); `CommentPreview` gained a
`showHeader` flag and a new sibling `CommentCountButton` (icon + count,
tap opens the thread). `VaultEntryCard` now composes all three inline
in one `Row`, with the actual reactor list and up-to-2 comment preview
lines (real content, not just buttons) following directly underneath --
takes noticeably less vertical space per post. `GlobalKey`s wire the
add-emoji button and comment-count button to reload their sibling list
widgets after a change, without lifting all the state up to the card.

**Text-only posts: action row moves below the text, not above.** Posts
with no media now render caption first, then the action row -- media
posts keep the original order (media, action row, caption) since that
part of the layout wasn't the complaint.

**Verified:** `flutter analyze` clean (same pre-existing info-level
lints only), and a `--split-per-abi` release build succeeded.

## 37. Explicit button colors, home privacy mask (blur images + mask text)

**Dialog buttons ("সংরক্ষণ", "মুছে ফেলুন", etc.) were rendering grey.**
`AppTheme._base()` never declared a `filledButtonTheme`/`textButtonTheme`,
so every `FilledButton`/`TextButton` in the app (used throughout for
dialog confirm/cancel actions) fell back to Flutter's own Material-3
default color resolution instead of our `ColorScheme.primary` reliably.
Now explicit: `filledButtonTheme` forces `backgroundColor: scheme.
primary` (white text), `textButtonTheme` forces `foregroundColor:
scheme.primary` -- no longer implicit/ambiguous.

**Home screen privacy mask.** New eye-icon toggle in the home app bar
(next to ফেভারিট) -- same idea as chat's existing privacy-mask toggle,
but for the whole feed: turning it on blurs every image/video thumbnail
(`ImageFiltered` + `ImageFilter.blur`, tap-to-fullscreen disabled while
blurred so there's no way to see it clearly) and replaces every text
caption with `'● ● ● ●'`. Unlike chat's mask (session-only, resets on
restart, per #39), this one is persisted locally via `SharedPreferences`
(`home_privacy_mask_enabled`) -- explicitly requested to survive app
restarts, since the whole point is being able to leave it on. Purely a
per-device rendering toggle, same as chat's -- never touches the actual
decrypted bytes/text or syncs to the other spouse.

**Verified:** `flutter analyze` clean (same pre-existing info-level
lints only), and a `--split-per-abi` release build succeeded.

## 38. Fix FAB/outlined-button color, promote privacy mask to app-wide

**Home screen's "+" FAB and outlined buttons were still off-color.**
`floatingActionButtonTheme` never set a `backgroundColor` -- Material
3's own FAB default reads `colorScheme.primaryContainer`, a pale/muted
tint, not the solid accent, which is almost certainly what read as
"washed out" on the home screen. Now explicit:
`backgroundColor: scheme.primary`. `outlinedButtonTheme` was missing
entirely too (foreground + border now `scheme.primary`). Between this
and #37's `filledButtonTheme`/`textButtonTheme`, every standard button
type Flutter has (`ElevatedButton`, `FilledButton`/`.tonal`,
`OutlinedButton`, `TextButton`) now explicitly resolves its color from
`scheme.primary` rather than leaving any of them to Material 3's own
(sometimes muted-by-design) default resolution.

**Privacy mask promoted from home-screen-only to app-wide, including
names.** Per explicit follow-up request -- the eye button stays on the
home app bar, but what it controls moved from `HomeTab`'s local state
into `SessionProvider.privacyMask` (global, `SharedPreferences`-backed,
loaded at `bootstrap()`). The blur itself is now baked directly into
the three shared low-level media widgets (`DecryptedThumbnail`,
`DecryptedFullImage`, `DecryptedVideoPlayer` in `decrypted_media.dart`)
via a shared `_applyPrivacyBlur()` helper that reads the same global
flag -- so every image and video anywhere in the app (home, favorites,
history, entry detail, Reel, chat bubbles, the full-screen viewer,
profile/reaction/comment avatar photos) blurs automatically with zero
per-screen wiring, "nothing excluded" as requested. Text follows the
same pattern per-screen (`VaultEntryCard`, `EntryDetailScreen`, Reel's
caption, `CommentSection`/`CommentPreview`) -- masked to `'● ● ● ●'`.
Spouse **names** are masked too: `authorDisplayName()` takes a `masked`
flag now, and every caller (`AuthorRow`, `CommentSection`'s name label)
passes the global flag through -- avatar *photos* were already covered
for free since `AuthorAvatar` renders through `DecryptedThumbnail`.
Chat's existing local eye toggle (session-only, from #39) still works
exactly as before as an independent additional override -- chat now
masks when *either* that local toggle or the new global flag is on.
Deliberately still device-local only, not synced to the other spouse
(unlike intimate mode) -- this is "who's looking over MY shoulder right
now", a personal-situation toggle, not a shared mood signal.

**Verified:** `flutter analyze` clean (same pre-existing info-level
lints only), and a `--split-per-abi` release build succeeded.

## 39. Real root cause of "green looks white everywhere": hardcoded white foreground in dark mode

#37/#38's button-color fixes weren't wrong, but they weren't the actual
root cause either -- the user came back angry, correctly insisting the
problem was systemic ("everywhere the brand color is used, the green
looks whitish") and asked for it to be found properly rather than
patched spot by spot again.

**Root cause:** `AppColors.halalGreenDark` (`0xFF7ED9A8`) is a
*deliberately* light pastel green -- it exists so accent text/icons
stay legible against a near-black dark-mode background, the same role
`AppColors.husband`'s blue or any other accent-on-dark color plays.
It was never meant to be used as a solid *fill* color with light text
on top. But `elevatedButtonTheme`, `filledButtonTheme`, and
`floatingActionButtonTheme` all hardcoded `foregroundColor: Colors.
white` -- fine in light mode (`scheme.primary` = the solid, darker
`0xFF2F9E63`), but in dark mode `scheme.primary` becomes that pale
mint, and **white text on a pale mint fill has almost no contrast** --
the button doesn't look "muted green", it looks like a near-white
blob with barely-legible white-on-white text. Chat's "mine" bubble had
the identical bug independently hardcoded (`color: mine ? Colors.white
: ...` for message text, timestamp, seen-tick, voice-player tint, and
the hidden-placeholder lock/stars) against the same primary-colored
background. This explains why the report was systemic and not
localized to one screen: every filled button *and* every chat bubble
you send shares the same broken pattern, and any phone with system
dark mode on (increasingly the Android default) would see it
everywhere at once.

**Fix:** replaced every hardcoded `Colors.white`/`Colors.white70` used
as foreground-on-primary with `scheme.onPrimary` (theme-level) /
`Theme.of(context).colorScheme.onPrimary` (chat bubble, computed once
per build) -- `onPrimary` is what Material 3 itself already computes as
the correctly-contrasting color for whatever `primary` actually is, so
it's white-on-dark-green in light mode and dark-on-pale-mint in dark
mode automatically, no manual light/dark branching needed anywhere.

**Also fixed while auditing:** `NavigationBarThemeData.iconTheme` was
never set at all -- the bottom nav's *selected* tab icon was falling
back to M3's own `onSecondaryContainer` default, completely unrelated
to the app's green/blue branding. Now explicit: `scheme.primary` when
selected, grey otherwise.

**Verified:** `flutter analyze` clean (same pre-existing info-level
lints only), and a `--split-per-abi` release build succeeded. Not yet
independently verified on a real dark-mode device by the user -- next
report should confirm whether this was the actual complete fix.

## 40. Dark-theme-only, chat privacy decoupled, nav/lifecycle fixes, reply + message reactions

**App is dark-theme-only now, per explicit request.** `AppTheme.light()`
is gone; `MaterialApp` only ever builds `AppTheme.dark()` (`themeMode:
ThemeMode.dark`). More importantly, the seed color itself changed: dark
mode no longer uses the separate pale `AppColors.halalGreenDark` --
it's the same solid, vivid `AppColors.halalGreen`/`intimateBlue` used
everywhere now, one color instead of a light/dark pair. Foreground
contrast is computed from the color's own actual brightness
(`ThemeData.estimateBrightnessForColor`), not assumed from the theme's
brightness -- `_onColorFor()` picks white or black87 based on the real
seed, which is what should have been done from the start instead of
#39's theme-brightness-based `onPrimary` reliance.

**Chat's privacy toggle is fully independent of the home screen's,
in either direction.** #38 had OR'd them together (either one hides
everything); per explicit follow-up, that was wrong -- chat's own
local eye toggle now has sole, full authority over chat's masking,
with zero relation to the home screen's global flag. To make that true
even for media (which is blurred by a *global* check baked into
`DecryptedThumbnail`/`DecryptedFullImage`/`DecryptedVideoPlayer`, see
#38), those three widgets gained a `forceShow` param that skips the
global check entirely; chat's photo/video bubbles always pass
`forceShow: true` since chat's own `if (hidden) ...` branch already
fully replaces the bubble with a placeholder when *chat's* toggle says
so -- nothing left for the global flag to additionally decide.

**Bottom nav: back button goes to the home tab first, not straight out
of the app.** `HomeShell` wrapped in `PopScope` (`canPop: _index == 0`)
-- pressing back on any other tab just switches to tab 0; only actually
exits once already there.

**Reopening after backgrounding stays on the same tab.** Backgrounding
re-locks the session (see #27), which tears down and later rebuilds
`HomeShell` from scratch once unlocked -- it always defaulted back to
the home tab regardless of what was open before. The active tab index
now lives in `SessionProvider.lastTabIndex` (never torn down across a
lock/unlock cycle) instead of purely local `HomeShell` state, and
`HomeShell` reads it back in `initState()`. Doesn't yet preserve a
*pushed* screen several levels deep in a tab's own navigation stack
(e.g. an open `EntryDetailScreen`) -- only which of the four bottom-nav
tabs was active; a full fix for the deeper case would mean not tearing
down `HomeShell` at all on lock (overlaying the biometric prompt on top
instead), which is a bigger change left for if it's actually needed.

**Chat: fixed landing mid-conversation instead of at the latest
message.** Root cause: `ScrollablePositionedList.builder` had no
`initialScrollIndex`, so its first frame always started at index 0 (the
oldest loaded message) -- long enough for `_onScrollPositionsChanged` to
see the top of the list and fire `_loadMoreHistory()` before the
animated scroll-to-bottom in `_load()` got a chance to run. That
history prepend's own `jumpTo()` then won the race, landing around the
middle of the (now-doubled) message list. Fixed by setting
`initialScrollIndex: _messages.length - 1` -- the very first frame
already renders at the bottom, so the premature top-of-list trigger
never happens.

**Chat: floating "jump to latest" button.** Appears once you've
scrolled up away from the bottom (tracked via the existing
`itemPositionsListener`), disappears once you're back at the bottom or
tap it to get there.

**Chat message reactions, WhatsApp/Telegram-style.** Long-press any
bubble to react with an emoji -- no backend change needed at all,
`chat_message` was already a valid `Reaction.target_type` server-side,
just never wired up client-side. `ReactionBar` split further:
`openReactionSheet()` is now a standalone top-level function (used by
both `ReactionAddButton` and chat's long-press handler), and each
message gets its own `ReactionList` (keyed per message id) rendered
underneath its bubble.

**Chat swipe-to-reply.** A quick rightward flick on a bubble
(`onHorizontalDragEnd` velocity check, not a full drag-tracked visual
reveal -- kept simple) starts a reply to that message: a preview bar
appears above the input (sender + a one-line snippet, with a way to
cancel), and the next thing sent carries a new `reply_to_id`. Required
an actual schema change -- `ChatMessage.reply_to_id`, a nullable self-
referential FK (`ON DELETE SET NULL`), added via the same idempotent
`ALTER TABLE ... ADD COLUMN IF NOT EXISTS` pattern already used for
`device_uuid`/TOTP columns, so no manual migration step. A bubble that
replies to something renders a small quoted box above its own content;
tapping it scrolls back to the original *if* it's still in the
currently-loaded page (older, already-paged-out messages just show a
generic "মূল মেসেজ" label instead of fetching it separately, to keep
this reasonably simple).

**Verified:** `flutter analyze` clean (same pre-existing info-level
lints, plus 2 new harmless `use_null_aware_elements` style suggestions
in `chat_service.dart`), backend imports cleanly (80 routes), and a
`--split-per-abi` release build succeeded.

## 19. Add Device (peer-to-peer pairing)

**Problem:** each role (`husband`/`wife`) can only be claimed once, ever
-- claiming is a one-time "create this half of the account" action, not
a login. There was no way to add a *second* device to an already-claimed
role (new phone, lost phone, or a spouse wanting the app on two of their
own devices) without deleting and re-registering the whole deployment.
This bit a real user: they'd claimed both roles from a single test phone
while trying things out, then had no path to move either role onto the
real, separate phones.

**Decision:** an already-authenticated device can generate a pairing
code (Settings -> "নতুন ডিভাইস যোগ করুন") containing
`{type: "device_pairing", server, role, spouse_id, vmk}`, shown as a QR
(and a copyable text fallback) with an explicit warning that it carries
the vault's real encryption key. This is peer-to-peer, exactly like the
existing admin-panel setup code -- it never touches the server, keeping
the E2E design intact (the server still never learns the VMK).

A new/blank device scans this from WelcomeScreen ("ইতিমধ্যে অ্যাকাউন্ট
আছে? এই ডিভাইসটা যোগ করুন" -- deliberately a separate entry point from
"সেটআপ কোড স্ক্যান করুন", since a setup code claims a role for the
*first* time and a pairing code adds a device to a role already claimed).
`SessionProvider.beginPairing()` stashes server/role/vmk locally (with
placeholder empty tokens) and flips state to `locked`, which reuses the
*existing* LoginScreen -> TotpVerifyScreen -> (optional) FaceVerifyScreen
flow completely unmodified -- the new device still has to pass a real
password + TOTP (+ face, if enabled) login against the server to obtain
its own tokens and Device row. No backend changes were needed; this is
purely a client-side onboarding path into endpoints that already existed.
