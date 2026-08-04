# Couple's Private Vault

A private, self-hosted, end-to-end encrypted vault app for a married couple.
See [project.md](project.md) for the full specification and
[DECISIONS.md](DECISIONS.md) for implementation choices made where the spec
was ambiguous.

This repo has two parts:
- `backend/` — FastAPI + PostgreSQL + MinIO backend, admin panel, all
  self-hosted via Docker Compose.
- `mobile_app/` — Flutter app (Android-first, iOS-compatible where
  reasonable), built from source and sideloaded as an APK. Not published to
  any app store.

## 1. Deploy the backend on your own VPS

Requirements: a Linux VPS (Ubuntu 22.04+ recommended) with a public IP, and
(optionally, for real HTTPS) a domain name pointed at it.

```bash
git clone <this-repo> couple-vault
cd couple-vault
./install.sh
```

The script installs Docker if missing, generates a `.env` with strong
random secrets, builds and starts every container (Postgres, MinIO,
CompreFace face-recognition service, the FastAPI backend, and Caddy for
automatic HTTPS), and prints next steps.

### CompreFace setup (one-time, manual)

The face-recognition admin UI is intentionally **not** exposed to the
public internet (see [DECISIONS.md](DECISIONS.md) §9). To create the
recognition API key the backend needs:

```bash
ssh -L 8085:localhost:8085 <you>@<your-vps-ip>
```

Then on your own machine, open `http://localhost:8085`, sign up for an
admin account, create an **Application**, add a **Recognition** service to
it, and copy the generated API key. Paste it into `.env` on the VPS as
`COMPREFACE_RECOGNITION_API_KEY=...`, then:

```bash
docker compose restart backend
```

### Admin panel

Visit `https://<your-domain>/admin`, set your admin password on first
visit, then click **Generate Setup Code** whenever a spouse needs to
onboard a new device. The code/QR is single-use per role (husband/wife) and
expires after 24 hours.

## 2. Build and install the Flutter app

```bash
cd mobile_app
flutter pub get
flutter build apk --release
```

Install the resulting APK (`build/app/outputs/flutter-apk/app-release.apk`)
on each spouse's phone (`adb install ...`, or transfer and sideload
directly — you'll need to allow "install from unknown sources" since this
is not distributed via any app store).

On first launch, each spouse scans (or manually enters) the setup code from
the admin panel, picks their role, sets a password, and registers their
face.

## 3. Everyday use

- Both spouses authenticate with password **and** face verification every
  time the app opens.
- Editing or deleting vault content always requires the other spouse's
  approval — see the in-app consent requests.
- A daily reminder notification nudges each spouse back to the app with a
  halal-framed message (see `backend/app/services/notifications.py` for the
  full message pool).
- A duress PIN (set in Settings) opens a decoy version of the app with no
  real content if you're ever forced to unlock it under pressure.

## Architecture

```
[ Flutter App (Husband) ]     [ Flutter App (Wife) ]
          |                              |
          |---------- HTTPS / WSS -------|
                        |
                 [ Your own VPS ]
                        |
  -------------------------------------------------
  |          |            |             |         |
 Caddy   FastAPI      PostgreSQL   MinIO (media)  CompreFace
(HTTPS)  backend      (ciphertext   (ciphertext    (self-hosted
         (relays      only)         only)          face match)
         ciphertext
         only)
```

The server never holds a decryption key and never sees plaintext content —
see [DECISIONS.md](DECISIONS.md) §1 for the full end-to-end encryption
design. FCM/APNs, if configured, is used only to deliver a generic
"you have a new update" wake-up push; no content or detail ever leaves the
VPS through it.

## Repo layout

```
backend/        FastAPI app, admin panel, Dockerfile
mobile_app/     Flutter app
deploy/caddy/   Caddyfile for automatic HTTPS
docker-compose.yml
install.sh
project.md      Source specification
DECISIONS.md    Implementation decisions log
```
