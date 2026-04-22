# security.py
from passlib.context import CryptContext

# bcrypt is widely used, safe default
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


class PasswordHasher:
    def hash(self, password: str) -> str:
        return pwd_context.hash(password)

    def verify(self, hashed_password: str, plain_password: str) -> bool:
        return pwd_context.verify(plain_password, hashed_password)


_hasher = PasswordHasher()


def get_password_hasher() -> PasswordHasher:
    return _hasher
