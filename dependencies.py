# dependencies.py

import logging
from typing import Optional
from datetime import datetime

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from firebase_admin import auth as firebase_auth

from auth_utils import firebase_app  # Ensure Firebase Admin SDK is initialized
from database import get_db
from models_core import User

security = HTTPBearer(auto_error=False)
logger = logging.getLogger("Golfer.auth")


def _token_sign_in_provider(decoded_token: dict) -> str:
    firebase_claim = decoded_token.get("firebase") or {}
    if not isinstance(firebase_claim, dict):
        return ""
    return str(firebase_claim.get("sign_in_provider") or "").strip().lower()


async def _get_firebase_user_from_token(
    credentials: Optional[HTTPAuthorizationCredentials],
    db: AsyncSession,
) -> Optional[User]:
    if not credentials:
        return None

    try:
        decoded_token = firebase_auth.verify_id_token(
            credentials.credentials, check_revoked=True
        )

        if (
            _token_sign_in_provider(decoded_token) == "password"
            and not bool(decoded_token.get("email_verified"))
        ):
            logger.info("auth_reject: unverified_password_email")
            return None

        firebase_uid = decoded_token["uid"]
        email = decoded_token.get("email", "").lower()
        name = decoded_token.get("name")
        picture = decoded_token.get("picture")

        # 1️⃣ Lookup by firebase UID
        result = await db.execute(select(User).where(User.firebase_uid == firebase_uid))
        user = result.scalar_one_or_none()

        if user:
            user.last_login = datetime.utcnow()
            await db.commit()
            return user

        # 2️⃣ Fallback: lookup by email
        if email:
            result = await db.execute(select(User).where(User.email == email))
            user = result.scalar_one_or_none()

            if user:
                user.firebase_uid = firebase_uid
                user.auth_method = "firebase"
                user.last_login = datetime.utcnow()

                if name and not user.username:
                    user.username = name
                if picture and not user.profile_pic:
                    user.profile_pic = picture

                await db.commit()
                return user

        return None

    except firebase_auth.InvalidIdTokenError:
        logger.info("auth_reject: invalid_id_token")
        return None
    except firebase_auth.ExpiredIdTokenError:
        logger.info("auth_reject: expired_id_token")
        return None
    except firebase_auth.RevokedIdTokenError:
        logger.info("auth_reject: revoked_id_token")
        return None
    except Exception as exc:
        logger.warning(f"auth_reject: token_verification_error: {exc}")
        return None


# -------------------------
# Auth dependencies
# -------------------------


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await _get_firebase_user_from_token(credentials, db)

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

    if getattr(user, "status", "").lower() == "inactive":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Account is deactivated",
        )

    return user


async def get_current_user_optional(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> Optional[User]:
    return await _get_firebase_user_from_token(credentials, db)


async def get_current_user_allow_inactive(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await _get_firebase_user_from_token(credentials, db)
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


# -------------------------
# Role guards
# -------------------------

def _role_is_admin(role: str | None) -> bool:
    value = (role or "").strip().lower()
    return value in {"admin", "admine"}  # legacy compatibility


def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not _role_is_admin(getattr(current_user, "role", "")):
        raise HTTPException(status_code=403, detail="Admin role required")
    return current_user


def require_user(current_user: User = Depends(get_current_user)) -> User:
    role = getattr(current_user, "role", "").lower()
    if role != "subscriber":
        raise HTTPException(status_code=403, detail="Subscriber access required")
    return current_user
