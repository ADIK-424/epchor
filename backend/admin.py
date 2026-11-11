import os

from db import polacz
from security import zahashuj_haslo


def utworz_administratora():
    """Tworzy początkowe konto DCA_JEDN, jeśli nie istnieje."""

    email = os.environ["ADMIN_EMAIL"].strip().lower()
    haslo = os.environ["ADMIN_PASSWORD"]
    imie = os.environ["ADMIN_FIRST_NAME"]
    nazwisko = os.environ["ADMIN_LAST_NAME"]

    if len(haslo) < 12:
        raise RuntimeError("Hasło administratora musi mieć co najmniej 12 znaków.")

    with polacz() as conn:
        uzytkownik = conn.execute(
            "SELECT id FROM users WHERE role = %s",
            ("DCA_JEDN",)
        ).fetchone()

        if uzytkownik is not None:
            return

        conn.execute(
            """
            INSERT INTO users (
                email, password_hash, role,
                first_name, last_name, status
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (email) DO NOTHING
            """,
            (
                email,
                zahashuj_haslo(haslo),
                "DCA_JEDN",
                imie,
                nazwisko,
                "AKTYWNY"
            )
        )
