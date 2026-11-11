from typing import Literal

import jwt
from fastapi import Depends, FastAPI, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from contextlib import asynccontextmanager

from admin import utworz_administratora
from pydantic import BaseModel, Field

from db import polacz
from security import zahashuj_haslo, sprawdz_haslo, utworz_token, odczytaj_token

@asynccontextmanager
async def lifespan(app: FastAPI):
    utworz_administratora()
    yield


app = FastAPI(title="ePchor API", lifespan=lifespan)


class RejestracjaUzytkownika(BaseModel):
    email: str
    password: str = Field(min_length=8)
    role: Literal["PCHOR", "DCA_KP"]
    first_name: str
    last_name: str
    rank: str | None = None
    study_group: str | None = None
    company_id: int
class LogowanieUzytkownika(BaseModel):
    email: str
    password: str



@app.get("/health")
def health():
    # sprawdza czy backend żyje i czy dogada się z bazą
    with polacz() as conn:
        liczba = conn.execute("SELECT count(*) FROM companies").fetchone()[0]
    return {"status": "ok", "kompanie_w_bazie": liczba}


@app.get("/companies")
def lista_kompanii():
    # lista wyboru kompanii (potrzebna przy rejestracji)
    with polacz() as conn:
        wiersze = conn.execute(
            "SELECT id, number, battalion FROM companies ORDER BY battalion, number"
        ).fetchall()
    return [{"id": w[0], "number": w[1], "battalion": w[2]} for w in wiersze]


@app.post("/register", status_code=201)
def rejestracja(dane: RejestracjaUzytkownika):
    email = dane.email.strip().lower()

    with polacz() as conn:
        # Sprawdzenie, czy wybrana kompania istnieje.
        kompania = conn.execute(
            "SELECT id FROM companies WHERE id = %s",
            (dane.company_id,)
        ).fetchone()

        if kompania is None:
            raise HTTPException(
                status_code=404,
                detail="Wybrana kompania nie istnieje."
            )

        # Zapis nowego użytkownika.
        uzytkownik = conn.execute(
            """
            INSERT INTO users (
                email, password_hash, role, first_name,
                last_name, rank, study_group, company_id
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (email) DO NOTHING
            RETURNING id, email, role, status
            """,
            (
                email,
                zahashuj_haslo(dane.password),
                dane.role,
                dane.first_name.strip(),
                dane.last_name.strip(),
                dane.rank,
                dane.study_group,
                dane.company_id
            )
        ).fetchone()

        if uzytkownik is None:
            raise HTTPException(
                status_code=409,
                detail="Konto z podanym adresem e-mail już istnieje."
            )

    return {
        "id": uzytkownik[0],
        "email": uzytkownik[1],
        "role": uzytkownik[2],
        "status": uzytkownik[3],
        "message": "Konto zostało utworzone i oczekuje na zatwierdzenie."
    }


@app.post("/login")
def logowanie(dane: LogowanieUzytkownika):
    email = dane.email.strip().lower()

    with polacz() as conn:
        uzytkownik = conn.execute(
            """
            SELECT id, email, password_hash, role, status
            FROM users
            WHERE email = %s
            """,
            (email,)
        ).fetchone()

    # Sprawdzenie, czy konto istnieje i hasło jest poprawne.
    if uzytkownik is None or not sprawdz_haslo(
        dane.password, uzytkownik[2]
    ):
        raise HTTPException(
            status_code=401,
            detail="Nieprawidłowy e-mail lub hasło."
        )

    # Konto musi zostać zatwierdzone.
    if uzytkownik[4] != "AKTYWNY":
        raise HTTPException(
            status_code=403,
            detail="Konto oczekuje na zatwierdzenie lub zostało odrzucone."
        )

    token = utworz_token({
        "user_id": uzytkownik[0],
        "role": uzytkownik[3]
    })

    return {
        "access_token": token,
        "token_type": "bearer",
        "user_id": uzytkownik[0],
        "email": uzytkownik[1],
        "role": uzytkownik[3]
    }



# ---------------------------------------------------------------- zalogowany użytkownik

# Odczytuje nagłówek "Authorization: Bearer <token>" (w Swaggerze: przycisk Authorize).
naglowek_tokenu = HTTPBearer()


def zalogowany(dane: HTTPAuthorizationCredentials = Depends(naglowek_tokenu)):
    """Zwraca zalogowanego użytkownika na podstawie tokenu. Używane przez Depends."""
    try:
        payload = odczytaj_token(dane.credentials)
    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=401,
            detail="Sesja wygasła, zaloguj się ponownie."
        )

    with polacz() as conn:
        w = conn.execute(
            """
            SELECT id, email, role, first_name, last_name,
                   rank, study_group, company_id, status
            FROM users
            WHERE id = %s
            """,
            (payload["user_id"],)
        ).fetchone()

    if w is None or w[8] != "AKTYWNY":
        raise HTTPException(status_code=401, detail="Konto jest nieaktywne.")

    return {
        "id": w[0],
        "email": w[1],
        "role": w[2],
        "first_name": w[3],
        "last_name": w[4],
        "rank": w[5],
        "study_group": w[6],
        "company_id": w[7]
    }


@app.get("/me")
def moje_dane(uzytkownik: dict = Depends(zalogowany)):
    return uzytkownik


# ---------------------------------------------------------------- zatwierdzanie kont

def moze_zatwierdzic(dowodca: dict, rola: str, kompania_id: int | None) -> bool:
    """D-ca jednostki zatwierdza d-ców kp, d-ca kp zatwierdza pchorów swojej kompanii."""
    if dowodca["role"] == "DCA_JEDN":
        return rola == "DCA_KP"
    if dowodca["role"] == "DCA_KP":
        return rola == "PCHOR" and kompania_id == dowodca["company_id"]
    return False


@app.get("/pending")
def konta_do_zatwierdzenia(dowodca: dict = Depends(zalogowany)):
    if dowodca["role"] == "PCHOR":
        raise HTTPException(status_code=403, detail="Brak uprawnień.")

    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT u.id, u.email, u.role, u.first_name, u.last_name,
                   u.rank, u.study_group, u.company_id, c.number, c.battalion
            FROM users u
            LEFT JOIN companies c ON c.id = u.company_id
            WHERE u.status = 'OCZEKUJE'
            ORDER BY u.created_at
            """
        ).fetchall()

    return [
        {
            "id": w[0],
            "email": w[1],
            "role": w[2],
            "first_name": w[3],
            "last_name": w[4],
            "rank": w[5],
            "study_group": w[6],
            "company_number": w[8],
            "battalion": w[9]
        }
        for w in wiersze
        if moze_zatwierdzic(dowodca, w[2], w[7])
    ]


def zmien_status(user_id: int, nowy_status: str, dowodca: dict):
    with polacz() as conn:
        konto = conn.execute(
            "SELECT role, company_id, status FROM users WHERE id = %s",
            (user_id,)
        ).fetchone()

        if konto is None:
            raise HTTPException(status_code=404, detail="Nie ma takiego konta.")

        if not moze_zatwierdzic(dowodca, konto[0], konto[1]):
            raise HTTPException(
                status_code=403,
                detail="Nie możesz rozpatrywać tego konta."
            )

        if konto[2] != "OCZEKUJE":
            raise HTTPException(
                status_code=409,
                detail="To konto zostało już rozpatrzone."
            )

        conn.execute(
            "UPDATE users SET status = %s WHERE id = %s",
            (nowy_status, user_id)
        )

    return {"id": user_id, "status": nowy_status}


@app.post("/users/{user_id}/approve")
def zatwierdz_konto(user_id: int, dowodca: dict = Depends(zalogowany)):
    return zmien_status(user_id, "AKTYWNY", dowodca)


@app.post("/users/{user_id}/reject")
def odrzuc_konto(user_id: int, dowodca: dict = Depends(zalogowany)):
    return zmien_status(user_id, "ODRZUCONY", dowodca)