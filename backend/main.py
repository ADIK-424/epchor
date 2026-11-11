from typing import Literal

from fastapi import FastAPI, HTTPException
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
