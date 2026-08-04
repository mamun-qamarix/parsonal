import pyotp

ISSUER_NAME = "Couple's Vault"


def generate_secret() -> str:
    return pyotp.random_base32()


def provisioning_uri(secret: str, account_name: str) -> str:
    """otpauth:// URI for QR display -- scan with Google Authenticator, Authy, etc."""
    return pyotp.totp.TOTP(secret).provisioning_uri(name=account_name, issuer_name=ISSUER_NAME)


def verify_code(secret: str, code: str) -> bool:
    if not code or not code.strip():
        return False
    totp = pyotp.TOTP(secret)
    return totp.verify(code.strip(), valid_window=1)
