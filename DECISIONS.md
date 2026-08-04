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
