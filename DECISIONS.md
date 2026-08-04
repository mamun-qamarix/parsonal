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

## 13. Repo layout

**Decision:** Monorepo at the project root:
- `/backend` — FastAPI backend, admin panel, Docker Compose, install script
- `/mobile_app` — Flutter app
- `project.md` — source spec
- `DECISIONS.md` — this file
