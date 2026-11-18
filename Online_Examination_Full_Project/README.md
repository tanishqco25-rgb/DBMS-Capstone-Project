# ExamFlow – Online Examination and Assessment Management System

A full-stack DBMS capstone demo using **Flask + MySQL + HTML/CSS/JavaScript**. It connects to the `online_exam_system` database created by `database.sql`.

## Features
- Student sign-in using enrollment number + email already present in `students`.
- Dashboard cards for students, examinations, question bank and generated results.
- Examination list and student registration.
- MCQ exam attempt page (correct answers are never sent to the browser).
- Submission is validated by the Flask backend and recorded in `responses`.
- Calls the database stored procedure `calculate_exam_result` to generate marks and pass/fail result.
- Student result history.
- Subject performance and exam ranking analytics.

> This is an academic prototype. Enrollment number + email is a demonstration sign-in method, not production-grade authentication. Add password hashing, admin authorization, CSRF protection, audit logging and server-side exam timing before production use.

## Requirements
- Windows 10/11, macOS or Linux
- Python 3.10+
- MySQL Server 8.0+
- MySQL Workbench (recommended)

## Step 1 – Create the database
1. Start MySQL Server.
2. Open MySQL Workbench and connect to your local MySQL instance.
3. Open `database.sql` and execute the full script.
4. The script creates/recreates the database `online_exam_system` and inserts sample data.

**Warning:** `database.sql` starts with `DROP DATABASE IF EXISTS online_exam_system;`. It will delete an existing database of that name. Back up any data before running it.

The SQL file replaces INTERSECT/EXCEPT demonstration statements with equivalent JOIN queries for wider MySQL compatibility. Window-function analytics require MySQL 8.0+.

## Step 2 – Configure the Flask app
1. Copy `.env.example` to a file named `.env`.
2. Open `.env` and set `DB_USER` and `DB_PASSWORD` to your MySQL credentials.
3. Keep `DB_NAME=online_exam_system`.
4. Set a unique `FLASK_SECRET_KEY`.

## Step 3 – Install and run on Windows
Option A: double-click `install_and_run_windows.bat`. It creates a virtual environment and installs dependencies. The batch file pauses so you can edit `.env` and import the SQL first; after that, run the server command below.

Option B: open Command Prompt in this folder and run:

```bat
py -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt
```

Then start the server:

```bat
python -m flask --app app run
```

## Step 4 – Run on macOS/Linux

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your MySQL credentials
flask --app app run
```

## Step 5 – Open the frontend
Visit: **http://127.0.0.1:5000**

Check database connectivity: **http://127.0.0.1:5000/api/health**

## Sample student login
The SQL script inserts these demo records:

| Enrollment number | Email |
|---|---|
| CSE26001 | aarav@example.edu |
| CSE26002 | diya@example.edu |
| CSE26003 | kabir@example.edu |
| ECE26001 | meera@example.edu |

Use the enrollment number and matching email together.

## Sample workflow
1. Sign in as `CSE26001` / `aarav@example.edu`.
2. Open Examinations.
3. Register for an exam if not already registered.
4. Click Start exam.
5. Select options and submit.
6. Open My Results to view the automatically generated score.
7. Open Analytics to inspect subject performance and rankings.

The sample SQL has pre-registered students for the sample exams and already generated results for the first exam. The DB uses `UNIQUE(exam_id, student_id)` for registration and `UNIQUE(exam_id, student_id, question_id)` for responses.

## Project structure

```text
online_exam_fullstack/
├── app.py
├── database.sql
├── requirements.txt
├── .env.example
├── install_and_run_windows.bat
├── install_linux_mac.sh
├── README.md
├── templates/
│   └── index.html
└── static/
    ├── app.js
    └── style.css
```

## Common troubleshooting

### `Access denied for user`
Check `DB_USER` and `DB_PASSWORD` in `.env`. Restart Flask after editing `.env`.

### `Unknown database 'online_exam_system'`
Import and execute `database.sql` in MySQL Workbench first.

### `Table ... doesn't exist` or `PROCEDURE ... doesn't exist`
The SQL setup did not finish. Check the MySQL Workbench Action Output for the first error and re-run the setup on a clean project database.

### `Can't connect to MySQL server`
Start the MySQL service and verify host/port (`127.0.0.1:3306` by default).

### Analytics window-function error
Use MySQL 8.0 or later. Check with `SELECT VERSION();`.

### Browser says server unavailable
Keep the terminal running where `flask --app app run` was started. Open `http://127.0.0.1:5000`, not the HTML file directly.

## API routes
- `GET /api/health`
- `POST /api/login`
- `POST /api/logout`
- `GET /api/me`
- `GET /api/dashboard`
- `GET /api/exams`
- `POST /api/exams/<exam_id>/register`
- `GET /api/exams/<exam_id>/questions`
- `POST /api/exams/<exam_id>/submit`
- `GET /api/results`
- `GET /api/admin/analytics`

## Notes about exam scoring
The current schema supports MCQ questions. The backend calls `calculate_exam_result`, which awards the mapped question marks for a correct answer and zero for an incorrect or unanswered question. The database stored procedure is the source of truth for result generation.
