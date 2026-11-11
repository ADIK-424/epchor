import os
from datetime import datetime, timedelta, timezone

import jwt
from dotenv import load_dotenv
from pwdlib import PasswordHash

load_dotenv()

password_hash = PasswordHash.recommended()

SECRET_KEY = os.environ.get("JWT_SECRET_KEY")

if not SECRET_KEY:
    raise RuntimeError("Brak JWT_SECRET_KEY w pliku .env")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60


def zahashuj_haslo(haslo: str) -> str:
    """Zwraca bezpieczny hash hasła."""
    return password_hash.hash(haslo)


def sprawdz_haslo(haslo: str, hash_hasla: str) -> bool:
    """Sprawdza hasło względem zapisanego hasha."""
    return password_hash.verify(haslo, hash_hasla)


def utworz_token(dane: dict[str, int | str]) -> str:
    """Tworzy token JWT ważny przez określony czas."""
    teraz = datetime.now(timezone.utc)

    payload = {
        **dane,
        "iat": teraz,
        "exp": teraz + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES),
    }

    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)


def odczytaj_token(token: str) -> dict[str, int | str]:
    """Weryfikuje token JWT i zwraca jego zawartość."""
    return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
