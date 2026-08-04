from datetime import datetime

from sqlalchemy import String, Boolean, DateTime, LargeBinary
from sqlalchemy.orm import Mapped, mapped_column

from app.database import Base
from app.models.common import UUIDPk, TimestampMixin


class SetupCode(Base, UUIDPk, TimestampMixin):
    """A shareable, admin-issued code. Persistent and reusable (not
    single-use, no expiry) -- either role can claim with it any number of
    times, and re-installing/re-adding an already-claimed role's device
    falls back to a normal login instead of a dead-end error. See
    DECISIONS.md. claimed_husband/claimed_wife/expires_at are legacy
    columns from the old single-use design, unused now but left in place
    on deployments that already have them rather than dropped."""
    __tablename__ = "setup_codes"

    token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    vmk_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    claimed_husband: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    claimed_wife: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)


class VaultKey(Base, UUIDPk, TimestampMixin):
    """The deployment's one-and-only Vault Master Key, persisted (encrypted
    at rest) independently of any SetupCode row so that regenerating or
    deleting a shareable setup code never changes the actual encryption
    key -- every device that has ever claimed a role, or ever will, must
    end up with this SAME key or they can't decrypt each other's content.
    Exactly one row is meant to ever exist. See DECISIONS.md."""
    __tablename__ = "vault_keys"

    vmk_encrypted: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
