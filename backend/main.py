import json
import time
import urllib.request
from datetime import date, timedelta
from typing import Literal
from urllib.parse import quote

import jwt
from fastapi import Depends, FastAPI, File, Form, HTTPException, Query, Response, UploadFile
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


# ---------------------------------------------------------------- pomocnicze

def wymagaj_roli(uzytkownik: dict, *role: str):
    if uzytkownik["role"] not in role:
        raise HTTPException(status_code=403, detail="Brak uprawnień.")


def sprawdz_plik(plik: UploadFile, rozszerzenia: tuple[str, ...]) -> bytes:
    """Sprawdza rozszerzenie i rozmiar wgrywanego pliku, zwraca jego zawartość."""
    if not plik.filename or not plik.filename.lower().endswith(rozszerzenia):
        raise HTTPException(
            status_code=400,
            detail="Niedozwolony typ pliku. Dozwolone: " + ", ".join(rozszerzenia)
        )
    tresc = plik.file.read()
    if len(tresc) > 10 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Plik jest za duży (max 10 MB).")
    return tresc


def odeslij_plik(tresc: bytes, nazwa: str) -> Response:
    # filename* pozwala na polskie znaki w nazwie pliku
    return Response(
        content=bytes(tresc),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(nazwa)}"}
    )


# ---------------------------------------------------------------- ogłoszenia

class NoweOgloszenie(BaseModel):
    title: str = Field(min_length=1)
    body: str = Field(min_length=1)


@app.get("/announcements")
def lista_ogloszen(uzytkownik: dict = Depends(zalogowany)):
    # widać ogłoszenia swojej kompanii i te dla całej jednostki (company_id NULL),
    # d-ca jednostki widzi wszystkie
    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT a.id, a.title, a.body, a.created_at, c.number,
                   au.rank, au.last_name, a.author_id,
                   EXISTS (SELECT 1 FROM announcement_reads r
                           WHERE r.announcement_id = a.id AND r.user_id = %s)
            FROM announcements a
            JOIN users au ON au.id = a.author_id
            LEFT JOIN companies c ON c.id = a.company_id
            WHERE a.company_id IS NULL OR a.company_id = %s OR %s
            ORDER BY a.created_at DESC
            """,
            (uzytkownik["id"], uzytkownik["company_id"], uzytkownik["role"] == "DCA_JEDN")
        ).fetchall()

    return [
        {
            "id": w[0],
            "title": w[1],
            "body": w[2],
            "created_at": w[3],
            "company_number": w[4],
            "author": f"{w[5] or ''} {w[6]}".strip(),
            "mine": w[7] == uzytkownik["id"],
            "read": w[8]
        }
        for w in wiersze
    ]


@app.post("/announcements", status_code=201)
def dodaj_ogloszenie(dane: NoweOgloszenie, uzytkownik: dict = Depends(zalogowany)):
    wymagaj_roli(uzytkownik, "DCA_KP", "DCA_JEDN")
    # d-ca kp pisze do swojej kompanii, d-ca jednostki do wszystkich
    kompania = None if uzytkownik["role"] == "DCA_JEDN" else uzytkownik["company_id"]

    with polacz() as conn:
        nowe_id = conn.execute(
            """
            INSERT INTO announcements (author_id, company_id, title, body)
            VALUES (%s, %s, %s, %s)
            RETURNING id
            """,
            (uzytkownik["id"], kompania, dane.title.strip(), dane.body.strip())
        ).fetchone()[0]

    return {"id": nowe_id}


@app.delete("/announcements/{ogloszenie_id}")
def usun_ogloszenie(ogloszenie_id: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        autor = conn.execute(
            "SELECT author_id FROM announcements WHERE id = %s", (ogloszenie_id,)
        ).fetchone()

        if autor is None:
            raise HTTPException(status_code=404, detail="Nie ma takiego ogłoszenia.")
        if autor[0] != uzytkownik["id"] and uzytkownik["role"] != "DCA_JEDN":
            raise HTTPException(status_code=403, detail="To nie jest Twoje ogłoszenie.")

        conn.execute("DELETE FROM announcements WHERE id = %s", (ogloszenie_id,))

    return {"id": ogloszenie_id}


@app.post("/announcements/{ogloszenie_id}/read")
def oznacz_przeczytane(ogloszenie_id: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        conn.execute(
            """
            INSERT INTO announcement_reads (user_id, announcement_id)
            VALUES (%s, %s)
            ON CONFLICT DO NOTHING
            """,
            (uzytkownik["id"], ogloszenie_id)
        )
    return {"id": ogloszenie_id, "read": True}


# ---------------------------------------------------------------- plan zajęć (watplan.coobie.dev)

WATPLAN = "https://watplan.coobie.dev/data"
_pamiec_planu = {}  # nazwa pliku -> (kiedy pobrany, dane)


def pobierz_json(nazwa: str):
    """Pobiera plik JSON z watplan i trzyma go w pamięci przez godzinę."""
    teraz = time.time()
    if nazwa in _pamiec_planu and teraz - _pamiec_planu[nazwa][0] < 3600:
        return _pamiec_planu[nazwa][1]

    zapytanie = urllib.request.Request(f"{WATPLAN}/{nazwa}", headers={"User-Agent": "ePchor"})
    with urllib.request.urlopen(zapytanie, timeout=20) as odp:
        dane = json.load(odp)

    _pamiec_planu[nazwa] = (teraz, dane)
    return dane


@app.get("/plan")
def plan_zajec(
    dzien: date | None = None,
    dni: int = Query(default=1, ge=1, le=14),
    uzytkownik: dict = Depends(zalogowany)
):
    # zajęcia grupy zalogowanego pchora od `dzien` przez `dni` dni
    grupa = uzytkownik["study_group"]
    if not grupa:
        return []

    od = dzien or date.today()
    daty = {(od + timedelta(days=i)).isoformat() for i in range(dni)}

    try:
        semestry = pobierz_json("semesters.json")
        zajecia = []
        # semestry mogą na siebie zachodzić (np. sesja poprawkowa), więc sprawdzamy wszystkie pasujące
        for s in semestry:
            if s["start"] <= max(daty) and s["end"] >= min(daty):
                wpisy = pobierz_json(f"entries-{s['id']}.json").get(grupa, [])
                # puste wpisy (bez nazwy przedmiotu) pomijamy
                zajecia += [w for w in wpisy if w["date"] in daty and w.get("title")]
    except Exception:
        raise HTTPException(status_code=502, detail="Nie udało się pobrać planu zajęć.")

    zajecia.sort(key=lambda w: (w["date"], w["timeStart"]))
    return [
        {
            "date": w["date"],
            "num": w["num"],
            "time_start": w["timeStart"],
            "time_end": w["timeEnd"],
            "title": w["title"],
            # nie każdy wpis w watplan ma salę i prowadzącego
            "type": w.get("type", ""),
            "room": ", ".join(w.get("room", [])),
            "prof": w.get("prof", "")
        }
        for w in zajecia
    ]


# ---------------------------------------------------------------- wnioski

class ZmianaStatusuWniosku(BaseModel):
    status: Literal["ROZPATRYWANY", "ZAAKCEPTOWANY", "ODRZUCONY"]
    comment: str | None = None


@app.post("/requests", status_code=201)
def zloz_wniosek(
    title: str = Form(min_length=1),
    plik: UploadFile = File(),
    uzytkownik: dict = Depends(zalogowany)
):
    wymagaj_roli(uzytkownik, "PCHOR")
    tresc = sprawdz_plik(plik, (".pdf",))

    with polacz() as conn:
        nowe_id = conn.execute(
            """
            INSERT INTO requests (user_id, company_id, title, file, file_name)
            VALUES (%s, %s, %s, %s, %s)
            RETURNING id
            """,
            (uzytkownik["id"], uzytkownik["company_id"], title.strip(), tresc, plik.filename)
        ).fetchone()[0]

    return {"id": nowe_id, "status": "ZŁOŻONY"}


@app.get("/requests/mine")
def moje_wnioski(uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT id, title, status, comment, created_at, file_name
            FROM requests
            WHERE user_id = %s
            ORDER BY created_at DESC
            """,
            (uzytkownik["id"],)
        ).fetchall()

    return [
        {"id": w[0], "title": w[1], "status": w[2], "comment": w[3],
         "created_at": w[4], "file_name": w[5]}
        for w in wiersze
    ]


@app.get("/requests")
def wnioski_kompanii(dowodca: dict = Depends(zalogowany)):
    wymagaj_roli(dowodca, "DCA_KP")

    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT r.id, r.title, r.status, r.comment, r.created_at, r.file_name,
                   u.rank, u.first_name, u.last_name
            FROM requests r
            JOIN users u ON u.id = r.user_id
            WHERE r.company_id = %s
            ORDER BY r.created_at DESC
            """,
            (dowodca["company_id"],)
        ).fetchall()

    return [
        {"id": w[0], "title": w[1], "status": w[2], "comment": w[3],
         "created_at": w[4], "file_name": w[5],
         "author": f"{w[6] or ''} {w[7]} {w[8]}".strip()}
        for w in wiersze
    ]


@app.patch("/requests/{wniosek_id}")
def zmien_status_wniosku(
    wniosek_id: int,
    dane: ZmianaStatusuWniosku,
    dowodca: dict = Depends(zalogowany)
):
    wymagaj_roli(dowodca, "DCA_KP")

    with polacz() as conn:
        wynik = conn.execute(
            """
            UPDATE requests SET status = %s, comment = %s
            WHERE id = %s AND company_id = %s
            RETURNING id
            """,
            (dane.status, dane.comment, wniosek_id, dowodca["company_id"])
        ).fetchone()

    if wynik is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego wniosku w Twojej kompanii.")
    return {"id": wniosek_id, "status": dane.status}


@app.get("/requests/{wniosek_id}/file")
def pobierz_wniosek(wniosek_id: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        w = conn.execute(
            "SELECT user_id, company_id, file, file_name FROM requests WHERE id = %s",
            (wniosek_id,)
        ).fetchone()

    if w is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego wniosku.")
    # plik widzi autor i d-ca jego kompanii
    wlasny = w[0] == uzytkownik["id"]
    dowodca = uzytkownik["role"] == "DCA_KP" and w[1] == uzytkownik["company_id"]
    if not (wlasny or dowodca):
        raise HTTPException(status_code=403, detail="Brak uprawnień.")

    return odeslij_plik(w[2], w[3])


# ---------------------------------------------------------------- wzory wniosków

ROZSZERZENIA_WZOROW = (".docx", ".doc")


@app.get("/templates")
def lista_wzorow(uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT id, name, file_name, updated_at
            FROM request_templates
            WHERE company_id = %s
            ORDER BY name
            """,
            (uzytkownik["company_id"],)
        ).fetchall()

    return [
        {"id": w[0], "name": w[1], "file_name": w[2], "updated_at": w[3]}
        for w in wiersze
    ]


@app.post("/templates", status_code=201)
def dodaj_wzor(
    name: str = Form(min_length=1),
    plik: UploadFile = File(),
    dowodca: dict = Depends(zalogowany)
):
    wymagaj_roli(dowodca, "DCA_KP")
    tresc = sprawdz_plik(plik, ROZSZERZENIA_WZOROW)

    with polacz() as conn:
        nowe_id = conn.execute(
            """
            INSERT INTO request_templates (company_id, name, file, file_name)
            VALUES (%s, %s, %s, %s)
            RETURNING id
            """,
            (dowodca["company_id"], name.strip(), tresc, plik.filename)
        ).fetchone()[0]

    return {"id": nowe_id}


@app.put("/templates/{wzor_id}")
def aktualizuj_wzor(wzor_id: int, plik: UploadFile = File(), dowodca: dict = Depends(zalogowany)):
    # podmiana pliku na nowszą wersję, nazwa wzoru zostaje
    wymagaj_roli(dowodca, "DCA_KP")
    tresc = sprawdz_plik(plik, ROZSZERZENIA_WZOROW)

    with polacz() as conn:
        wynik = conn.execute(
            """
            UPDATE request_templates
            SET file = %s, file_name = %s, updated_at = now()
            WHERE id = %s AND company_id = %s
            RETURNING id
            """,
            (tresc, plik.filename, wzor_id, dowodca["company_id"])
        ).fetchone()

    if wynik is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego wzoru w Twojej kompanii.")
    return {"id": wzor_id}


@app.delete("/templates/{wzor_id}")
def usun_wzor(wzor_id: int, dowodca: dict = Depends(zalogowany)):
    wymagaj_roli(dowodca, "DCA_KP")

    with polacz() as conn:
        wynik = conn.execute(
            "DELETE FROM request_templates WHERE id = %s AND company_id = %s RETURNING id",
            (wzor_id, dowodca["company_id"])
        ).fetchone()

    if wynik is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego wzoru w Twojej kompanii.")
    return {"id": wzor_id}


@app.get("/templates/{wzor_id}/file")
def pobierz_wzor(wzor_id: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        w = conn.execute(
            "SELECT file, file_name FROM request_templates WHERE id = %s AND company_id = %s",
            (wzor_id, uzytkownik["company_id"])
        ).fetchone()

    if w is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego wzoru.")
    return odeslij_plik(w[0], w[1])


# ---------------------------------------------------------------- grafik służb

@app.post("/duties", status_code=201)
def wgraj_grafik(
    month: int = Form(ge=1, le=12),
    year: int = Form(ge=2020, le=2100),
    comment: str | None = Form(default=None),
    plik: UploadFile = File(),
    dowodca: dict = Depends(zalogowany)
):
    wymagaj_roli(dowodca, "DCA_KP")
    tresc = sprawdz_plik(plik, (".pdf", ".xlsx", ".xls"))

    # jeden grafik na miesiąc - ponowne wgranie podmienia stary plik
    with polacz() as conn:
        nowe_id = conn.execute(
            """
            INSERT INTO duty_schedules (company_id, month, year, file, file_name, comment)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (company_id, month, year) DO UPDATE
            SET file = EXCLUDED.file, file_name = EXCLUDED.file_name,
                comment = EXCLUDED.comment, created_at = now()
            RETURNING id
            """,
            (dowodca["company_id"], month, year, tresc, plik.filename, comment)
        ).fetchone()[0]

    return {"id": nowe_id}


@app.get("/duties")
def grafiki_sluzb(month: int, year: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        wiersze = conn.execute(
            """
            SELECT d.id, d.company_id, c.number, c.battalion, d.file_name,
                   d.comment, d.created_at
            FROM duty_schedules d
            JOIN companies c ON c.id = d.company_id
            WHERE d.month = %s AND d.year = %s
            ORDER BY c.battalion, c.number
            """,
            (month, year)
        ).fetchall()

    return [
        {"id": w[0], "company_number": w[2], "battalion": w[3], "file_name": w[4],
         "comment": w[5], "created_at": w[6], "own": w[1] == uzytkownik["company_id"]}
        for w in wiersze
    ]


@app.get("/duties/{grafik_id}/file")
def pobierz_grafik(grafik_id: int, uzytkownik: dict = Depends(zalogowany)):
    with polacz() as conn:
        w = conn.execute(
            "SELECT file, file_name FROM duty_schedules WHERE id = %s", (grafik_id,)
        ).fetchone()

    if w is None:
        raise HTTPException(status_code=404, detail="Nie ma takiego grafiku.")
    return odeslij_plik(w[0], w[1])
