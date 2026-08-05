import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.deps import get_current_spouse
from app.models.profile import Profile
from app.models.misc import CountdownTarget, AppSetting
from app.models.user import Spouse, RoleEnum
from app.models.common import utcnow
from app.schemas.common import b64_to_bytes, bytes_to_b64
from app.schemas.profile import ProfileUpdate, ProfileOut, CountdownSet, CountdownOut, AppSettingOut, AppSettingUpdate

router = APIRouter(tags=["profile"])


async def _get_or_create_profile(db: AsyncSession, spouse_id: uuid.UUID) -> Profile:
    result = await db.execute(select(Profile).where(Profile.spouse_id == spouse_id))
    profile = result.scalar_one_or_none()
    if profile is None:
        profile = Profile(spouse_id=spouse_id)
        db.add(profile)
        await db.commit()
        await db.refresh(profile)
    return profile


def _out(profile: Profile, role: str) -> ProfileOut:
    return ProfileOut(
        spouse_id=profile.spouse_id, role=role,
        enc_display_name=bytes_to_b64(profile.enc_display_name), enc_bio=bytes_to_b64(profile.enc_bio),
        enc_anniversary_dates=bytes_to_b64(profile.enc_anniversary_dates),
        profile_photo_asset_id=profile.profile_photo_asset_id, updated_at=profile.updated_at,
    )


@router.get("/profile/{role}", response_model=ProfileOut)
async def get_profile(role: str, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    target = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(role)))
    target_spouse = target.scalar_one_or_none()
    if target_spouse is None:
        raise HTTPException(status_code=404, detail="Not registered yet")
    profile = await _get_or_create_profile(db, target_spouse.id)
    return _out(profile, role)


@router.put("/profile/me", response_model=ProfileOut)
async def update_my_profile(payload: ProfileUpdate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    profile = await _get_or_create_profile(db, spouse.id)
    if payload.enc_display_name is not None:
        profile.enc_display_name = b64_to_bytes(payload.enc_display_name)
    if payload.enc_bio is not None:
        profile.enc_bio = b64_to_bytes(payload.enc_bio)
    if payload.enc_anniversary_dates is not None:
        profile.enc_anniversary_dates = b64_to_bytes(payload.enc_anniversary_dates)
    if payload.profile_photo_asset_id is not None:
        profile.profile_photo_asset_id = payload.profile_photo_asset_id
    profile.updated_at = utcnow()
    await db.commit()
    await db.refresh(profile)
    return _out(profile, spouse.role.value)


@router.put("/profile/{role}", response_model=ProfileOut)
async def update_profile(role: str, payload: ProfileUpdate, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    """Either spouse can edit either profile -- same shared-trust model as
    everywhere else in the app (device management, vault entries, etc.).
    /profile/me above is kept for backward compatibility but the client
    now always calls this instead, passing whichever role's tab is open.
    See DECISIONS.md."""
    target = await db.execute(select(Spouse).where(Spouse.role == RoleEnum(role)))
    target_spouse = target.scalar_one_or_none()
    if target_spouse is None:
        raise HTTPException(status_code=404, detail="Not registered yet")

    profile = await _get_or_create_profile(db, target_spouse.id)
    if payload.enc_display_name is not None:
        profile.enc_display_name = b64_to_bytes(payload.enc_display_name)
    if payload.enc_bio is not None:
        profile.enc_bio = b64_to_bytes(payload.enc_bio)
    if payload.enc_anniversary_dates is not None:
        profile.enc_anniversary_dates = b64_to_bytes(payload.enc_anniversary_dates)
    if payload.profile_photo_asset_id is not None:
        profile.profile_photo_asset_id = payload.profile_photo_asset_id
    profile.updated_at = utcnow()
    await db.commit()
    await db.refresh(profile)
    return _out(profile, role)


# ---------- Countdown to next meet ----------

@router.get("/countdown", response_model=CountdownOut | None)
async def get_countdown(db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    result = await db.execute(select(CountdownTarget).order_by(CountdownTarget.updated_at.desc()).limit(1))
    target = result.scalar_one_or_none()
    if target is None:
        return None
    return CountdownOut(target_datetime=target.target_datetime, set_by=target.set_by, enc_note=bytes_to_b64(target.enc_note), updated_at=target.updated_at)


@router.put("/countdown", response_model=CountdownOut)
async def set_countdown(payload: CountdownSet, spouse: Spouse = Depends(get_current_spouse), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(CountdownTarget).order_by(CountdownTarget.updated_at.desc()).limit(1))
    target = result.scalar_one_or_none()
    enc_note = b64_to_bytes(payload.enc_note) if payload.enc_note else None
    if target is None:
        target = CountdownTarget(target_datetime=payload.target_datetime, set_by=spouse.id, enc_note=enc_note)
        db.add(target)
    else:
        target.target_datetime = payload.target_datetime
        target.set_by = spouse.id
        target.enc_note = enc_note
        target.updated_at = utcnow()
    await db.commit()
    await db.refresh(target)
    return CountdownOut(target_datetime=target.target_datetime, set_by=target.set_by, enc_note=bytes_to_b64(target.enc_note), updated_at=target.updated_at)


# ---------- App settings (e.g. Favorite Lines toggle) ----------

@router.get("/settings/{key}", response_model=AppSettingOut)
async def get_setting(key: str, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    row = result.scalar_one_or_none()
    if row is None:
        defaults = {"favorite_lines_enabled": "true"}
        return AppSettingOut(key=key, value=defaults.get(key, ""))
    return AppSettingOut(key=row.key, value=row.value)


@router.put("/settings/{key}", response_model=AppSettingOut)
async def set_setting(key: str, payload: AppSettingUpdate, db: AsyncSession = Depends(get_db), spouse: Spouse = Depends(get_current_spouse)):
    result = await db.execute(select(AppSetting).where(AppSetting.key == key))
    row = result.scalar_one_or_none()
    if row:
        row.value = payload.value
    else:
        row = AppSetting(key=key, value=payload.value)
        db.add(row)
    await db.commit()
    return AppSettingOut(key=key, value=payload.value)
