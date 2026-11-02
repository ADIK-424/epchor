# Backend ePchor: wszystkie endpointy API.
from fastapi import FastAPI
from db import polacz

app = FastAPI(title="ePchor API")


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