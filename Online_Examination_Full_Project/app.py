import os
from datetime import datetime
from functools import wraps

import mysql.connector
from mysql.connector import Error
from dotenv import load_dotenv

load_dotenv()
from flask import Flask, render_template, request, jsonify, session

app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "change-this-development-secret")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "online_exam_system"),
    "autocommit": False,
}

def get_connection():
    return mysql.connector.connect(**DB_CONFIG)

def db_error_message(exc):
    # Avoid exposing passwords or connection internals to the browser.
    return f"Database operation failed: {exc.msg if hasattr(exc, 'msg') else 'Check MySQL connection and schema.'}"

def student_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("student_id"):
            return jsonify({"error": "Please sign in with your student credentials."}), 401
        return fn(*args, **kwargs)
    return wrapper

@app.route("/")
def index():
    return render_template("index.html")

@app.get("/api/health")
def health():
    try:
        conn = get_connection()
        conn.close()
        return jsonify({"ok": True, "database": DB_CONFIG["database"]})
    except Error:
        return jsonify({"ok": False, "message": "Cannot connect to MySQL. Check .env and start MySQL."}), 503

@app.post("/api/login")
def login():
    data = request.get_json(silent=True) or {}
    enrollment = (data.get("enrollment_no") or "").strip()
    email = (data.get("email") or "").strip().lower()
    if not enrollment or not email:
        return jsonify({"error": "Enter both enrollment number and email address."}), 400
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT student_id, enrollment_no, first_name, last_name, email
            FROM students
            WHERE enrollment_no=%s AND LOWER(email)=LOWER(%s) AND student_status='ACTIVE'
        """, (enrollment, email))
        student = cur.fetchone()
        cur.close()
        conn.close()
        if not student:
            return jsonify({"error": "Student not found. Check the enrollment number and email. Use a sample student from the README for testing."}), 401
        session["student_id"] = student["student_id"]
        session["student_name"] = (student["first_name"] + " " + (student["last_name"] or "")).strip()
        session["enrollment_no"] = student["enrollment_no"]
        return jsonify({"student": {"name": session["student_name"], "enrollment_no": student["enrollment_no"]}})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.post("/api/logout")
def logout():
    session.clear()
    return jsonify({"ok": True})

@app.get("/api/me")
def me():
    if not session.get("student_id"):
        return jsonify({"student": None})
    return jsonify({"student": {"name": session.get("student_name"), "enrollment_no": session.get("enrollment_no")}})

@app.get("/api/dashboard")
def dashboard():
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("SELECT COUNT(*) AS total_students FROM students WHERE student_status='ACTIVE'")
        students = cur.fetchone()["total_students"]
        cur.execute("SELECT COUNT(*) AS total_exams FROM examinations")
        exams = cur.fetchone()["total_exams"]
        cur.execute("SELECT COUNT(*) AS total_questions FROM questions WHERE is_active=1")
        questions = cur.fetchone()["total_questions"]
        cur.execute("SELECT COUNT(*) AS total_results FROM results")
        results = cur.fetchone()["total_results"]
        cur.execute("""
            SELECT e.exam_id, e.exam_title, e.exam_type, e.start_time, e.end_time,
                   e.duration_minutes, e.total_marks, e.pass_marks, e.exam_status,
                   s.subject_name, s.subject_code
            FROM examinations e JOIN subjects s ON s.subject_id=e.subject_id
            ORDER BY e.start_time DESC
        """)
        exam_rows = cur.fetchall()
        cur.close()
        conn.close()
        for row in exam_rows:
            row["start_time"] = row["start_time"].strftime("%d %b %Y, %I:%M %p")
            row["end_time"] = row["end_time"].strftime("%d %b %Y, %I:%M %p")
        return jsonify({"stats": {"students": students, "exams": exams, "questions": questions, "results": results}, "exams": exam_rows})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.get("/api/exams")
def exams():
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT e.exam_id, e.exam_title, e.exam_type, e.start_time, e.end_time,
                   e.duration_minutes, e.total_marks, e.pass_marks, e.exam_status,
                   s.subject_name, s.subject_code,
                   (SELECT COUNT(*) FROM exam_questions eq WHERE eq.exam_id=e.exam_id) AS question_count
            FROM examinations e JOIN subjects s ON s.subject_id=e.subject_id
            ORDER BY e.start_time DESC
        """)
        rows = cur.fetchall()
        if session.get("student_id"):
            for row in rows:
                cur.execute("SELECT registration_status FROM exam_registrations WHERE exam_id=%s AND student_id=%s",
                            (row["exam_id"], session["student_id"]))
                reg = cur.fetchone()
                row["registration_status"] = reg["registration_status"] if reg else None
        cur.close()
        conn.close()
        for row in rows:
            row["start_time"] = row["start_time"].strftime("%d %b %Y, %I:%M %p")
            row["end_time"] = row["end_time"].strftime("%d %b %Y, %I:%M %p")
        return jsonify({"exams": rows})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.post("/api/exams/<int:exam_id>/register")
@student_required
def register_exam(exam_id):
    try:
        conn = get_connection()
        cur = conn.cursor()
        cur.execute("SELECT exam_id, exam_status FROM examinations WHERE exam_id=%s", (exam_id,))
        exam = cur.fetchone()
        if not exam:
            conn.close()
            return jsonify({"error": "Examination not found."}), 404
        cur.execute("""
            INSERT INTO exam_registrations (exam_id, student_id)
            VALUES (%s, %s)
            ON DUPLICATE KEY UPDATE registration_status='REGISTERED'
        """, (exam_id, session["student_id"]))
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"ok": True, "message": "Registration successful."})
    except Error as exc:
        try: conn.rollback(); conn.close()
        except Exception: pass
        return jsonify({"error": db_error_message(exc)}), 400

@app.get("/api/exams/<int:exam_id>/questions")
@student_required
def exam_questions(exam_id):
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT registration_status FROM exam_registrations
            WHERE exam_id=%s AND student_id=%s
        """, (exam_id, session["student_id"]))
        registration = cur.fetchone()
        if not registration or registration["registration_status"] == "WITHDRAWN":
            cur.close(); conn.close()
            return jsonify({"error": "Register for this examination before starting it."}), 403
        cur.execute("""
            SELECT q.question_id, q.question_text, q.difficulty, eq.marks, eq.question_order
            FROM exam_questions eq JOIN questions q ON q.question_id=eq.question_id
            WHERE eq.exam_id=%s AND q.is_active=1
            ORDER BY eq.question_order
        """, (exam_id,))
        questions = cur.fetchall()
        for q in questions:
            cur.execute("""
                SELECT option_id, option_label, option_text
                FROM question_options WHERE question_id=%s ORDER BY option_label
            """, (q["question_id"],))
            q["options"] = cur.fetchall()
        cur.execute("SELECT exam_title, duration_minutes, total_marks FROM examinations WHERE exam_id=%s", (exam_id,))
        exam = cur.fetchone()
        cur.close(); conn.close()
        return jsonify({"exam": exam, "questions": questions})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.post("/api/exams/<int:exam_id>/submit")
@student_required
def submit_exam(exam_id):
    data = request.get_json(silent=True) or {}
    answers = data.get("answers") or {}
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT registration_status FROM exam_registrations
            WHERE exam_id=%s AND student_id=%s
        """, (exam_id, session["student_id"]))
        reg = cur.fetchone()
        if not reg or reg["registration_status"] == "WITHDRAWN":
            conn.rollback(); cur.close(); conn.close()
            return jsonify({"error": "You are not registered for this examination."}), 403

        # Validate each submitted option belongs to the question assigned to this exam.
        for question_id, option_id in answers.items():
            cur.execute("""
                SELECT 1
                FROM exam_questions eq
                JOIN question_options qo ON qo.question_id=eq.question_id
                WHERE eq.exam_id=%s AND eq.question_id=%s AND qo.option_id=%s
            """, (exam_id, int(question_id), int(option_id)))
            if not cur.fetchone():
                conn.rollback(); cur.close(); conn.close()
                return jsonify({"error": "An answer contains an invalid question or option."}), 400
            cur.execute("""
                INSERT INTO responses (exam_id, student_id, question_id, selected_option_id)
                VALUES (%s, %s, %s, %s)
                ON DUPLICATE KEY UPDATE selected_option_id=VALUES(selected_option_id),
                                        answered_at=CURRENT_TIMESTAMP
            """, (exam_id, session["student_id"], int(question_id), int(option_id)))

        cur.execute("CALL calculate_exam_result(%s, %s)", (exam_id, session["student_id"]))
        # Consume any stored-procedure result sets before commit.
        while cur.nextset():
            pass
        cur.execute("""
            UPDATE exam_registrations SET registration_status='COMPLETED'
            WHERE exam_id=%s AND student_id=%s
        """, (exam_id, session["student_id"]))
        conn.commit()
        cur.execute("""
            SELECT marks_obtained, total_marks, percentage, result_status
            FROM results WHERE exam_id=%s AND student_id=%s
        """, (exam_id, session["student_id"]))
        result = cur.fetchone()
        cur.close(); conn.close()
        return jsonify({"ok": True, "result": result})
    except (Error, ValueError) as exc:
        try: conn.rollback(); conn.close()
        except Exception: pass
        return jsonify({"error": db_error_message(exc) if isinstance(exc, Error) else "Invalid answer data."}), 400

@app.get("/api/results")
@student_required
def my_results():
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("""
            SELECT r.exam_id, e.exam_title, s.subject_name, r.marks_obtained,
                   r.total_marks, r.percentage, r.result_status, r.evaluated_at
            FROM results r
            JOIN examinations e ON e.exam_id=r.exam_id
            JOIN subjects s ON s.subject_id=e.subject_id
            WHERE r.student_id=%s ORDER BY r.evaluated_at DESC
        """, (session["student_id"],))
        rows = cur.fetchall()
        for row in rows:
            row["evaluated_at"] = row["evaluated_at"].strftime("%d %b %Y, %I:%M %p")
        cur.close(); conn.close()
        return jsonify({"results": rows})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.get("/api/admin/analytics")
def analytics():
    try:
        conn = get_connection()
        cur = conn.cursor(dictionary=True)
        cur.execute("SELECT * FROM vw_subject_performance ORDER BY subject_name")
        subjects = cur.fetchall()
        cur.execute("""
            SELECT e.exam_title, s.enrollment_no, CONCAT(s.first_name,' ',COALESCE(s.last_name,'')) AS student_name,
                   r.marks_obtained, r.total_marks, r.percentage,
                   RANK() OVER (PARTITION BY r.exam_id ORDER BY r.percentage DESC) AS exam_rank
            FROM results r JOIN examinations e ON e.exam_id=r.exam_id
            JOIN students s ON s.student_id=r.student_id
            ORDER BY e.exam_id, exam_rank
        """)
        rankings = cur.fetchall()
        cur.close(); conn.close()
        return jsonify({"subjects": subjects, "rankings": rankings})
    except Error as exc:
        return jsonify({"error": db_error_message(exc)}), 503

@app.errorhandler(404)
def not_found(_):
    return jsonify({"error": "Endpoint not found."}), 404

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=int(os.getenv("PORT", "5000")), debug=os.getenv("FLASK_DEBUG", "0") == "1")
