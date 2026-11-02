# Połączenie z bazą danych.
import os
import psycopg
from dotenv import load_dotenv

load_dotenv()  # szuka pliku .env i wczytuje zmienne z niego

DATABASE_URL = os.environ["DATABASE_URL"]


def polacz():
    """Nowe połączenie z bazą danych"""
    return psycopg.connect(DATABASE_URL)