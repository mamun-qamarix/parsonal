#!/usr/bin/env bash
# One-command installer for the Couple's Private Vault backend stack.
# Run this on your own VPS (Ubuntu/Debian recommended) as a user with sudo.
set -euo pipefail

cd "$(dirname "$0")"

echo "== Couple's Private Vault — installer =="

# ---------- 1. Docker ----------
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found — installing via get.docker.com ..."
  curl -fsSL https://get.docker.com | sh
  sudo usermod -aG docker "$USER" || true
  echo "Docker installed. You may need to log out and back in for group changes to apply."
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' (v2 plugin) not found. Please install Docker Compose v2 and re-run this script."
  exit 1
fi

# ---------- 2. .env ----------
if [ -f .env ]; then
  echo ".env already exists — skipping prompts. Delete it and re-run to regenerate."
else
  echo
  read -rp "Domain name for HTTPS (e.g. vault.example.com), or leave blank to use this server's IP with a self-signed cert: " DOMAIN_INPUT
  DOMAIN_VALUE="${DOMAIN_INPUT:-$(curl -fs https://api.ipify.org || echo localhost)}"

  gen_secret() { openssl rand -hex 24; }

  cat > .env <<EOF
DOMAIN=${DOMAIN_VALUE}

DB_USER=vault
DB_PASSWORD=$(gen_secret)
DB_NAME=vault

MINIO_ROOT_USER=vaultmedia
MINIO_ROOT_PASSWORD=$(gen_secret)

COMPREFACE_DB_PASSWORD=$(gen_secret)
COMPREFACE_ADMIN_EMAIL=admin@${DOMAIN_VALUE}
COMPREFACE_ADMIN_PASSWORD=$(gen_secret)
# Fill this in after the one-time CompreFace setup step (see README.md):
COMPREFACE_RECOGNITION_API_KEY=

JWT_SECRET=$(gen_secret)
ADMIN_PANEL_SECRET=$(gen_secret)

# Optional: Firebase Cloud Messaging server key, for OS-level push wake-ups
# while the app is fully backgrounded/killed. Payloads stay generic (see
# project.md §7) regardless. Leave blank to rely on WebSocket-only push.
FCM_SERVER_KEY=
FCM_PROJECT_ID=

CORS_ORIGINS=*
EOF
  echo ".env generated with fresh random secrets."
fi

# shellcheck disable=SC1091
set -a; source .env; set +a

if [ -z "${DOMAIN:-}" ] || [ "$DOMAIN" = "localhost" ]; then
  echo "NOTE: no real domain configured — Caddy will not be able to obtain a"
  echo "Let's Encrypt certificate. Edit DOMAIN in .env once you have one, or"
  echo "keep using this for local/self-signed testing only."
fi

# ---------- 3. Bring up the stack ----------
echo
echo "Building and starting containers (this can take a few minutes on first run)..."
docker compose up -d --build

echo
echo "Waiting for the backend to become healthy..."
for i in $(seq 1 30); do
  if docker compose exec -T backend curl -fs http://localhost:8000/health >/dev/null 2>&1; then
    echo "Backend is up."
    break
  fi
  sleep 5
done

# ---------- 4. Try to auto-provision the CompreFace API key ----------
# Best-effort: CompreFace's own console API isn't a stable public contract
# (unlike its recognition API, which app/services/face_verify.py uses and
# which IS stable/documented). If this doesn't work against your CompreFace
# version, it's not a failure of the install — just do the manual step
# printed below instead. See DECISIONS.md §9 and backend/scripts/provision_compreface.py.
echo
echo "Attempting automatic face-recognition service setup..."
COMPREFACE_AUTOSETUP_OK=0
if docker compose run --rm -T \
    -v "$(pwd)/.env:/workspace/.env" \
    -e ENV_FILE_PATH=/workspace/.env \
    backend python scripts/provision_compreface.py; then
  COMPREFACE_AUTOSETUP_OK=1
  echo "Face-recognition service configured automatically."
  echo "Restarting backend to pick up the new key..."
  set -a; source .env; set +a
  docker compose up -d backend
else
  echo "Automatic setup didn't complete — you'll need the one manual step below."
fi

if [ "$COMPREFACE_AUTOSETUP_OK" = "1" ]; then
  cat <<EOF

================================================================
 Install complete — including face-recognition setup.

 1. Open https://${DOMAIN}/admin (or http://<server-ip>/admin if
    you skipped the domain) and set your admin password.

 2. From the admin panel, generate a setup code/QR for each spouse
    to scan in the Flutter app.
================================================================
EOF
else
  cat <<EOF

================================================================
 Install complete — one manual step left.

 1. Open https://${DOMAIN}/admin (or http://<server-ip>/admin if
    you skipped the domain) and set your admin password.

 2. One-time face-recognition setup (see README.md "CompreFace setup"):
      ssh -L 8085:localhost:8085 <you>@<this-server>
    then open http://localhost:8085 locally, create an account +
    application + recognition service, copy the API key into
    COMPREFACE_RECOGNITION_API_KEY in .env, then run:
      docker compose up -d backend

 3. From the admin panel, generate a setup code/QR for each spouse
    to scan in the Flutter app.
================================================================
EOF
fi
