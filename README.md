# ePchor

Aplikacja mobilna dla podchorążych WAT - projekt na zajęcia (Adrian, Miłosz).

- **mobile/** - aplikacja Flutter (Android)
- **backend/** - API w FastAPI
- baza PostgreSQL w Dockerze (`docker-compose.yml`)

Plan zajęć jest pobierany z [watplan.coobie.dev](https://watplan.coobie.dev) według grupy podanej przy rejestracji.

## Uruchomienie

```bash
cp .env.example .env          # i wpisać swoje hasła / klucz JWT
docker compose up -d
docker exec -i epchor-db psql -U epchor -d epchor < backend/schema.sql
```

Backend:

```bash
cd backend
python -m venv .venv
source .venv/Scripts/activate
pip install -r requirements.txt
fastapi dev main.py            # Swagger: http://localhost:8000/docs
```

Aplikacja (emulator Androida, backend musi działać):

```bash
cd mobile
flutter pub get
flutter run
```

Testy: `pytest -v` w `backend/` i `flutter test` w `mobile/`.

## Role

| Rola | Co może |
|---|---|
| Podchorąży (`PCHOR`) | plan zajęć z przypomnieniem 15 min przed, ogłoszenia, grafik służb, składanie wniosków (PDF) i podgląd statusu |
| Dowódca kompanii (`DCA_KP`) | zatwierdza pchorów swojej kompanii, ogłoszenia, wnioski, grafik służb, wzory wniosków (.docx) |
| Dowódca jednostki (`DCA_JEDN`) | zatwierdza dowódców kompanii, ogłoszenia dla całej jednostki. Konto zakładane automatycznie z `ADMIN_*` w `.env` |
