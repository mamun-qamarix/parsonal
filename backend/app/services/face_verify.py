import httpx

from app.config import get_settings

settings = get_settings()


class FaceVerifyService:
    """Thin client for a self-hosted CompreFace recognition service.

    All calls stay within the user's own Docker network (compreface-api
    container) -- no cloud API is used.
    """

    def __init__(self) -> None:
        self.base_url = settings.compreface_url.rstrip("/")
        self.api_key = settings.compreface_recognition_api_key

    def _headers(self) -> dict:
        return {"x-api-key": self.api_key}

    async def enroll(self, subject: str, image_bytes: bytes) -> None:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{self.base_url}/api/v1/recognition/faces",
                params={"subject": subject},
                headers=self._headers(),
                files={"file": ("face.jpg", image_bytes, "image/jpeg")},
            )
            resp.raise_for_status()

    async def verify(self, subject: str, image_bytes: bytes) -> bool:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.post(
                f"{self.base_url}/api/v1/recognition/recognize",
                headers=self._headers(),
                files={"file": ("face.jpg", image_bytes, "image/jpeg")},
                data={"limit": "1", "face_plugins": ""},
            )
            resp.raise_for_status()
            data = resp.json()
            results = data.get("result", [])
            if not results:
                return False
            best = results[0]
            subjects = best.get("subjects", [])
            if not subjects:
                return False
            top = subjects[0]
            return top.get("subject") == subject and top.get("similarity", 0) >= settings.compreface_similarity_threshold

    async def delete_subject(self, subject: str) -> None:
        async with httpx.AsyncClient(timeout=30) as client:
            resp = await client.delete(
                f"{self.base_url}/api/v1/recognition/faces",
                params={"subject": subject},
                headers=self._headers(),
            )
            if resp.status_code not in (200, 404):
                resp.raise_for_status()


face_verify_service = FaceVerifyService()
