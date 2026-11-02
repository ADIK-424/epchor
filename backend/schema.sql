-- Tabele bazy ePchor.
-- Plik można uruchamiać wiele razy: IF NOT EXISTS i ON CONFLICT nic nie zepsują.

-- Tabela kompanie
CREATE TABLE IF NOT EXISTS companies (
    id        SERIAL PRIMARY KEY,
    number    INT NOT NULL,
    battalion INT NOT NULL,
    UNIQUE (number, battalion)
);

-- Tabela uzytkownicy
CREATE TABLE IF NOT EXISTS users (
    id            SERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL CHECK (role IN ('PCHOR', 'DCA_KP', 'DCA_JEDN')),
    first_name    TEXT NOT NULL,
    last_name     TEXT NOT NULL,
    rank          TEXT,
    study_group   TEXT,
    company_id    INT REFERENCES companies(id),
    status        TEXT NOT NULL DEFAULT 'OCZEKUJE'
                  CHECK (status IN ('OCZEKUJE', 'AKTYWNY', 'ODRZUCONY')),
    created_at    TIMESTAMP NOT NULL DEFAULT now()
);

-- Kompanie startowe (my stworzylismy przykladowe dla WAT)
INSERT INTO companies (number, battalion) VALUES
    (1, 1), (2, 1), (3, 1), (4, 1), (5, 1),
    (6, 2), (7, 2), (8, 2), (9, 2), (10, 2),
    (11, 3), (12, 3), (13, 3), (14, 3), (15, 3),
    (16, 4), (17, 4), (18, 4), (19, 4), (20, 4),
    (21, 5), (22, 5), (23, 5), (24, 5), (25, 5)
ON CONFLICT DO NOTHING;