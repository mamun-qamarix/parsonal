"""One-time, best-effort automated provisioning of a CompreFace recognition
API key, run by install.sh right after the stack comes up.

CompreFace's *recognition* API (/api/v1/recognition/...) is stable and
publicly documented -- that's what app/services/face_verify.py talks to.
The *admin* API used here to create an Organization -> Application ->
Recognition Service and mint an API key is CompreFace's own internal
console API. It works against CompreFace 1.x as tested informally by the
community, but has no formal public contract and could change between
CompreFace versions.

This script is therefore intentionally best-effort:
- Every step is guarded; any unexpected response exits non-zero with a
  clear message instead of half-provisioning something.
- install.sh treats a non-zero exit here as "fall back to the manual
  SSH-tunnel steps in README.md", never as a fatal install error.
- Success is verified independently: after writing the key, this script
  calls the real recognition API's /api/v1/recognition/faces list
  endpoint with the new key to confirm it actually works before reporting
  success.
"""
import os
import re
import sys
import time

import httpx

ADMIN_BASE = os.environ.get("COMPREFACE_ADMIN_INTERNAL_URL", "http://compreface-fe:80")
API_BASE = os.environ.get("COMPREFACE_API_INTERNAL_URL", "http://compreface-api:8000")
ADMIN_EMAIL = os.environ["COMPREFACE_ADMIN_EMAIL"]
ADMIN_PASSWORD = os.environ["COMPREFACE_ADMIN_PASSWORD"]
ENV_FILE = os.environ.get("ENV_FILE_PATH", "/workspace/.env")
APP_NAME = "CoupleVault"
SERVICE_NAME = "vault-face-recognition"


def log(msg: str) -> None:
    print(f"[provision_compreface] {msg}", file=sys.stderr, flush=True)


def wait_for(client: httpx.Client, url: str, attempts: int = 30, delay: float = 5.0) -> bool:
    for i in range(attempts):
        try:
            resp = client.get(url, timeout=5)
            if resp.status_code < 500:
                return True
        except httpx.HTTPError:
            pass
        time.sleep(delay)
    return False


def main() -> int:
    with httpx.Client(base_url=ADMIN_BASE, timeout=15) as client:
        log("Waiting for CompreFace admin console to become reachable...")
        if not wait_for(client, "/"):
            log("CompreFace admin console never became reachable. Skipping automated setup.")
            return 1

        log("Logging in...")
        login = client.post("/api/v1/login", json={"email": ADMIN_EMAIL, "password": ADMIN_PASSWORD})
        if login.status_code not in (200, 201):
            log(f"Login failed (HTTP {login.status_code}). Skipping automated setup.")
            return 1

        # Find or create an organization.
        orgs = client.get("/api/v1/org")
        if orgs.status_code != 200:
            log(f"Could not list organizations (HTTP {orgs.status_code}). Skipping automated setup.")
            return 1
        org_list = orgs.json()
        org_list = org_list.get("orgs", org_list) if isinstance(org_list, dict) else org_list
        if org_list:
            org_id = org_list[0].get("id") or org_list[0].get("guid")
        else:
            created = client.post("/api/v1/org", json={"name": "CoupleVaultOrg"})
            if created.status_code not in (200, 201):
                log(f"Could not create organization (HTTP {created.status_code}). Skipping automated setup.")
                return 1
            body = created.json()
            org_id = body.get("id") or body.get("guid")
        if not org_id:
            log("Could not determine organization id. Skipping automated setup.")
            return 1

        # Find or create the application.
        apps = client.get(f"/api/v1/org/{org_id}/app")
        app_id = None
        if apps.status_code == 200:
            app_list = apps.json()
            app_list = app_list.get("apps", app_list) if isinstance(app_list, dict) else app_list
            for a in app_list:
                if a.get("name") == APP_NAME:
                    app_id = a.get("id") or a.get("guid")
                    break
        if app_id is None:
            created = client.post(f"/api/v1/org/{org_id}/app", json={"name": APP_NAME})
            if created.status_code not in (200, 201):
                log(f"Could not create application (HTTP {created.status_code}). Skipping automated setup.")
                return 1
            app_id = created.json().get("id") or created.json().get("guid")
        if not app_id:
            log("Could not determine application id. Skipping automated setup.")
            return 1

        # Find or create the recognition service (model) and grab its API key.
        services = client.get(f"/api/v1/org/{org_id}/app/{app_id}/model")
        api_key = None
        if services.status_code == 200:
            svc_list = services.json()
            svc_list = svc_list.get("models", svc_list) if isinstance(svc_list, dict) else svc_list
            for s in svc_list:
                if s.get("name") == SERVICE_NAME:
                    api_key = s.get("apiKey") or s.get("api_key")
                    break
        if api_key is None:
            created = client.post(
                f"/api/v1/org/{org_id}/app/{app_id}/model",
                json={"name": SERVICE_NAME, "type": "RECOGNITION_SERVICE"},
            )
            if created.status_code not in (200, 201):
                log(f"Could not create recognition service (HTTP {created.status_code}). Skipping automated setup.")
                return 1
            body = created.json()
            api_key = body.get("apiKey") or body.get("api_key")
        if not api_key:
            log("Could not determine recognition service API key. Skipping automated setup.")
            return 1

    # Verify the key actually works against the real, stable recognition API
    # before trusting it.
    log("Verifying the API key against the recognition API...")
    with httpx.Client(base_url=API_BASE, timeout=15) as api_client:
        check = api_client.get("/api/v1/recognition/faces", headers={"x-api-key": api_key})
        if check.status_code != 200:
            log(f"API key did not work against the recognition API (HTTP {check.status_code}). Skipping automated setup.")
            return 1

    if not write_env_key(api_key):
        return 1

    log(f"Success. COMPREFACE_RECOGNITION_API_KEY set in {ENV_FILE}.")
    return 0


def write_env_key(api_key: str) -> bool:
    try:
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            content = f.read()
    except OSError as exc:
        log(f"Could not read {ENV_FILE}: {exc}")
        return False

    if re.search(r"^COMPREFACE_RECOGNITION_API_KEY=.*$", content, flags=re.MULTILINE):
        content = re.sub(
            r"^COMPREFACE_RECOGNITION_API_KEY=.*$",
            f"COMPREFACE_RECOGNITION_API_KEY={api_key}",
            content,
            flags=re.MULTILINE,
        )
    else:
        content += f"\nCOMPREFACE_RECOGNITION_API_KEY={api_key}\n"

    try:
        with open(ENV_FILE, "w", encoding="utf-8") as f:
            f.write(content)
    except OSError as exc:
        log(f"Could not write {ENV_FILE}: {exc}")
        return False
    return True


if __name__ == "__main__":
    sys.exit(main())
