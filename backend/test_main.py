from fastapi.testclient import TestClient

from main import app

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