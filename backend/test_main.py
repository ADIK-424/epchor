import uuid

import pytest
from fastapi.testclient import TestClient

from db import polacz
from main import app
from security import zahashuj_haslo

klient = TestClient(app)


def test_health():
    odp = klient.get("/health")
    assert odp.status_code == 200
    assert odp.json()["status"] == "ok"


def test_lista_kompanii():
    odp = klient.get("/companies")
    assert odp.status_code == 200
    kompanie = odp.json()
    assert len(kompanie) > 0
    assert set(kompanie[0].keys()) == {"id", "number", "battalion"}


def test_kompanie_posortowane():
    odp = klient.get("/companies")
    kompanie = odp.json()

    kolejnosc = [
        (k["battalion"], k["number"])
        for k in kompanie
    ]

    assert kolejnosc == sorted(kolejnosc)


# ---------------------------------------------------------------- konta testowe

HASLO = "haslo-testowe-123"
utworzone = []  # id kont założonych w testach, usuwane po każdym teście


@pytest.fixture(autouse=True)
def sprzatanie():
    yield  # tu wykonuje się test
    with polacz() as conn:
        conn.execute("DELETE FROM users WHERE id = ANY(%s)", (utworzone,))
    utworzone.clear()


def nowe_konto(rola, kompania_id=1, status="AKTYWNY"):
    """Zakłada konto prosto w bazie i zwraca (id, email)."""
    email = f"test-{uuid.uuid4().hex[:8]}@test.pl"
    with polacz() as conn:
        id_konta = conn.execute(
            """
            INSERT INTO users (email, password_hash, role, first_name,
                               last_name, company_id, status)
            VALUES (%s, %s, %s, 'Test', 'Testowy', %s, %s)
            RETURNING id
            """,
            (email, zahashuj_haslo(HASLO), rola, kompania_id, status)
        ).fetchone()[0]
    utworzone.append(id_konta)
    return id_konta, email


def naglowek(email):
    """Loguje się i zwraca nagłówek z tokenem do kolejnych zapytań."""
    odp = klient.post("/login", json={"email": email, "password": HASLO})
    return {"Authorization": f"Bearer {odp.json()['access_token']}"}


# ---------------------------------------------------------------- rejestracja i logowanie

def test_rejestracja_i_logowanie_niezatwierdzonego():
    email = f"test-{uuid.uuid4().hex[:8]}@test.pl"
    odp = klient.post("/register", json={
        "email": email,
        "password": HASLO,
        "role": "PCHOR",
        "first_name": "Jan",
        "last_name": "Testowy",
        "company_id": 1
    })
    assert odp.status_code == 201
    assert odp.json()["status"] == "OCZEKUJE"
    utworzone.append(odp.json()["id"])

    odp = klient.post("/login", json={"email": email, "password": HASLO})
    assert odp.status_code == 403


def test_zle_haslo():
    _, email = nowe_konto("PCHOR")
    odp = klient.post("/login", json={"email": email, "password": "zle-haslo"})
    assert odp.status_code == 401


def test_me():
    _, email = nowe_konto("PCHOR")
    odp = klient.get("/me", headers=naglowek(email))
    assert odp.status_code == 200
    assert odp.json()["email"] == email


def test_me_bez_tokenu():
    assert klient.get("/me").status_code in (401, 403)


# ---------------------------------------------------------------- zatwierdzanie

def test_dca_kp_zatwierdza_pchora_swojej_kompanii():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    pchor_id, pchor = nowe_konto("PCHOR", kompania_id=1, status="OCZEKUJE")

    oczekujacy = klient.get("/pending", headers=naglowek(dca)).json()
    assert pchor_id in [k["id"] for k in oczekujacy]

    odp = klient.post(f"/users/{pchor_id}/approve", headers=naglowek(dca))
    assert odp.status_code == 200

    odp = klient.post("/login", json={"email": pchor, "password": HASLO})
    assert odp.status_code == 200


def test_dca_kp_nie_zatwierdza_cudzej_kompanii():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    pchor_id, _ = nowe_konto("PCHOR", kompania_id=2, status="OCZEKUJE")

    oczekujacy = klient.get("/pending", headers=naglowek(dca)).json()
    assert pchor_id not in [k["id"] for k in oczekujacy]

    odp = klient.post(f"/users/{pchor_id}/approve", headers=naglowek(dca))
    assert odp.status_code == 403


def test_pchor_nie_zatwierdza():
    _, pchor = nowe_konto("PCHOR")
    inny_id, _ = nowe_konto("PCHOR", status="OCZEKUJE")

    odp = klient.post(f"/users/{inny_id}/approve", headers=naglowek(pchor))
    assert odp.status_code == 403


def test_dca_jedn_zatwierdza_tylko_dca_kp():
    _, dca_jedn = nowe_konto("DCA_JEDN", kompania_id=None)
    dca_kp_id, _ = nowe_konto("DCA_KP", status="OCZEKUJE")
    pchor_id, _ = nowe_konto("PCHOR", status="OCZEKUJE")

    odp = klient.post(f"/users/{pchor_id}/approve", headers=naglowek(dca_jedn))
    assert odp.status_code == 403

    odp = klient.post(f"/users/{dca_kp_id}/approve", headers=naglowek(dca_jedn))
    assert odp.status_code == 200


def test_odrzucone_konto_nie_loguje_sie():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    pchor_id, pchor = nowe_konto("PCHOR", kompania_id=1, status="OCZEKUJE")

    odp = klient.post(f"/users/{pchor_id}/reject", headers=naglowek(dca))
    assert odp.status_code == 200

    odp = klient.post("/login", json={"email": pchor, "password": HASLO})
    assert odp.status_code == 403


# ---------------------------------------------------------------- ogłoszenia

def test_ogloszenie_dca_kp_widzi_tylko_swoja_kompania():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    _, pchor1 = nowe_konto("PCHOR", kompania_id=1)
    _, pchor2 = nowe_konto("PCHOR", kompania_id=2)

    odp = klient.post("/announcements", headers=naglowek(dca),
                      json={"title": "Zbiórka", "body": "Jutro 7:00 przed budynkiem"})
    assert odp.status_code == 201
    nowe_id = odp.json()["id"]

    widzi1 = [o["id"] for o in klient.get("/announcements", headers=naglowek(pchor1)).json()]
    widzi2 = [o["id"] for o in klient.get("/announcements", headers=naglowek(pchor2)).json()]
    assert nowe_id in widzi1
    assert nowe_id not in widzi2


def test_pchor_nie_dodaje_ogloszen():
    _, pchor = nowe_konto("PCHOR")
    odp = klient.post("/announcements", headers=naglowek(pchor),
                      json={"title": "x", "body": "y"})
    assert odp.status_code == 403


def test_ogloszenie_przeczytane():
    _, dca = nowe_konto("DCA_JEDN", kompania_id=None)
    _, pchor = nowe_konto("PCHOR")
    nowe_id = klient.post("/announcements", headers=naglowek(dca),
                          json={"title": "Dla wszystkich", "body": "test"}).json()["id"]

    def przeczytane():
        lista = klient.get("/announcements", headers=naglowek(pchor)).json()
        return [o for o in lista if o["id"] == nowe_id][0]["read"]

    assert przeczytane() is False
    klient.post(f"/announcements/{nowe_id}/read", headers=naglowek(pchor))
    assert przeczytane() is True


# ---------------------------------------------------------------- plan zajęć

def test_plan_zajec(monkeypatch):
    # zamiast prawdziwego watplan podstawiamy własne dane
    dane = {
        "semesters.json": [{"id": "20261", "start": "2026-10-01", "end": "2027-02-20"}],
        "entries-20261.json": {"WCY23KB1S0": [
            {"title": "Bazy danych", "type": "Wykład", "room": ["100 S"], "date": "2026-11-30",
             "prof": "dr X", "num": 2, "timeStart": "09:50", "timeEnd": "11:25"},
            {"title": "Matematyka", "type": "Ćwiczenia", "room": [], "date": "2026-11-30",
             "prof": "dr Y", "num": 1, "timeStart": "08:00", "timeEnd": "09:35"},
            {"title": "Inny dzień", "type": "Wykład", "room": [], "date": "2026-12-01",
             "prof": "dr Z", "num": 1, "timeStart": "08:00", "timeEnd": "09:35"},
        ]},
    }
    monkeypatch.setattr("main.pobierz_json", lambda nazwa: dane[nazwa])

    pchor_id, pchor = nowe_konto("PCHOR")
    with polacz() as conn:
        conn.execute("UPDATE users SET study_group = 'WCY23KB1S0' WHERE id = %s", (pchor_id,))

    odp = klient.get("/plan?dzien=2026-11-30", headers=naglowek(pchor))
    assert odp.status_code == 200
    assert [z["title"] for z in odp.json()] == ["Matematyka", "Bazy danych"]

    odp = klient.get("/plan?dzien=2026-11-30&dni=2", headers=naglowek(pchor))
    assert len(odp.json()) == 3


# ---------------------------------------------------------------- wnioski

PDF = ("wniosek.pdf", b"%PDF-1.4 test", "application/pdf")


def test_wniosek_od_zlozenia_do_akceptacji():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    _, pchor = nowe_konto("PCHOR", kompania_id=1)

    odp = klient.post("/requests", headers=naglowek(pchor),
                      data={"title": "Przepustka"}, files={"plik": PDF})
    assert odp.status_code == 201
    wniosek_id = odp.json()["id"]

    wnioski_dcy = [w["id"] for w in klient.get("/requests", headers=naglowek(dca)).json()]
    assert wniosek_id in wnioski_dcy

    odp = klient.patch(f"/requests/{wniosek_id}", headers=naglowek(dca),
                       json={"status": "ZAAKCEPTOWANY", "comment": "Zgoda"})
    assert odp.status_code == 200

    moje = klient.get("/requests/mine", headers=naglowek(pchor)).json()
    assert moje[0]["status"] == "ZAAKCEPTOWANY"
    assert moje[0]["comment"] == "Zgoda"

    odp = klient.get(f"/requests/{wniosek_id}/file", headers=naglowek(dca))
    assert odp.content == PDF[1]


def test_wniosek_tylko_pdf():
    _, pchor = nowe_konto("PCHOR")
    odp = klient.post("/requests", headers=naglowek(pchor), data={"title": "x"},
                      files={"plik": ("wniosek.exe", b"MZ", "application/octet-stream")})
    assert odp.status_code == 400


def test_dca_innej_kompanii_nie_zmienia_wniosku():
    _, dca2 = nowe_konto("DCA_KP", kompania_id=2)
    _, pchor = nowe_konto("PCHOR", kompania_id=1)
    wniosek_id = klient.post("/requests", headers=naglowek(pchor),
                             data={"title": "x"}, files={"plik": PDF}).json()["id"]

    odp = klient.patch(f"/requests/{wniosek_id}", headers=naglowek(dca2),
                       json={"status": "ODRZUCONY"})
    assert odp.status_code == 404


# ---------------------------------------------------------------- wzory i grafik

DOCX = ("Wniosek o przepustkę.docx", b"PK test v1", "application/octet-stream")


def test_wzor_dodanie_i_aktualizacja():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    _, pchor = nowe_konto("PCHOR", kompania_id=1)

    odp = klient.post("/templates", headers=naglowek(dca),
                      data={"name": "Przepustka"}, files={"plik": DOCX})
    assert odp.status_code == 201
    wzor_id = odp.json()["id"]

    odp = klient.put(f"/templates/{wzor_id}", headers=naglowek(dca),
                     files={"plik": ("nowy.docx", b"PK test v2", "application/octet-stream")})
    assert odp.status_code == 200

    wzory = klient.get("/templates", headers=naglowek(pchor)).json()
    assert [w["name"] for w in wzory if w["id"] == wzor_id] == ["Przepustka"]
    assert klient.get(f"/templates/{wzor_id}/file", headers=naglowek(pchor)).content == b"PK test v2"

    klient.delete(f"/templates/{wzor_id}", headers=naglowek(dca))


def test_grafik_sluzb():
    _, dca = nowe_konto("DCA_KP", kompania_id=1)
    _, pchor = nowe_konto("PCHOR", kompania_id=1)

    odp = klient.post("/duties", headers=naglowek(dca),
                      data={"month": 1, "year": 2099, "comment": "Wersja 1"},
                      files={"plik": ("grafik.pdf", b"%PDF grafik", "application/pdf")})
    assert odp.status_code == 201
    grafik_id = odp.json()["id"]

    grafiki = klient.get("/duties?month=1&year=2099", headers=naglowek(pchor)).json()
    moj = [g for g in grafiki if g["id"] == grafik_id][0]
    assert moj["own"] is True
    assert moj["comment"] == "Wersja 1"

    with polacz() as conn:
        conn.execute("DELETE FROM duty_schedules WHERE id = %s", (grafik_id,))
