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