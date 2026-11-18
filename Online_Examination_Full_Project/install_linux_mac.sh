#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
if [ ! -f .env ]; then cp .env.example .env; fi
echo "Edit .env with your MySQL password, then import database.sql in MySQL Workbench."
echo "Run: flask --app app run"
