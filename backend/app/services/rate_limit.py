import time
from collections import defaultdict

from fastapi import HTTPException, Request

# In-memory, per-process sliding-window limiter. The backend runs as a
# single uvicorn process/container (see docker-compose.yml), so this is
# consistent without needing Redis. Keyed by (bucket, client IP) so one
# noisy IP can't lock out unrelated ones, and different endpoints don't
# share a budget.
_attempts: dict[str, list[float]] = defaultdict(list)


def rate_limit(bucket: str, max_attempts: int, window_seconds: int):
    """FastAPI dependency: 429s once `max_attempts` requests land from the
    same client IP within `window_seconds` for this bucket. Guards
    password/TOTP/admin-login endpoints against brute-forcing -- see
    DECISIONS.md."""

    async def dependency(request: Request) -> None:
        client_ip = request.client.host if request.client else "unknown"
        key = f"{bucket}:{client_ip}"
        now = time.time()
        window = _attempts[key]
        cutoff = now - window_seconds
        while window and window[0] < cutoff:
            window.pop(0)
        if len(window) >= max_attempts:
            raise HTTPException(status_code=429, detail="Too many attempts. Please wait a few minutes and try again.")
        window.append(now)

    return dependency
