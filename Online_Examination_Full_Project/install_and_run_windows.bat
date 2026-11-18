@echo off
cd /d "%~dp0"
if not exist .venv (
  py -m venv .venv
)
call .venv\Scripts\activate
python -m pip install --upgrade pip
pip install -r requirements.txt
if not exist .env copy .env.example .env
echo.
echo IMPORTANT: Edit .env and set your MySQL password before continuing.
echo Then import database.sql in MySQL Workbench.
pause
python -m flask --app app run
pause
