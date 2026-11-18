-- ============================================================
-- ONLINE EXAMINATION AND ASSESSMENT MANAGEMENT SYSTEM
-- DBMS Capstone Project | MySQL 8.0.31+
-- ============================================================
-- Run in MySQL Workbench or mysql CLI as an administrator.
-- The script recreates the project database.
DROP DATABASE IF EXISTS online_exam_system;
CREATE DATABASE online_exam_system;
USE online_exam_system;

-- 1. MASTER TABLES
CREATE TABLE departments (
    department_id INT AUTO_INCREMENT PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE semesters (
    semester_id INT AUTO_INCREMENT PRIMARY KEY,
    semester_number TINYINT NOT NULL UNIQUE,
    academic_year VARCHAR(9) NOT NULL,
    CHECK (semester_number BETWEEN 1 AND 12)
);

CREATE TABLE students (
    student_id INT AUTO_INCREMENT PRIMARY KEY,
    enrollment_no VARCHAR(25) NOT NULL UNIQUE,
    first_name VARCHAR(60) NOT NULL,
    last_name VARCHAR(60),
    email VARCHAR(120) NOT NULL UNIQUE,
    department_id INT NOT NULL,
    admission_date DATE NOT NULL,
    student_status ENUM('ACTIVE','INACTIVE','GRADUATED') DEFAULT 'ACTIVE',
    CONSTRAINT fk_student_department FOREIGN KEY (department_id)
        REFERENCES departments(department_id)
);

CREATE TABLE subjects (
    subject_id INT AUTO_INCREMENT PRIMARY KEY,
    subject_code VARCHAR(20) NOT NULL UNIQUE,
    subject_name VARCHAR(120) NOT NULL,
    department_id INT NOT NULL,
    credits TINYINT NOT NULL DEFAULT 3,
    CONSTRAINT fk_subject_department FOREIGN KEY (department_id)
        REFERENCES departments(department_id),
    CHECK (credits BETWEEN 1 AND 10)
);

CREATE TABLE student_semesters (
    student_id INT NOT NULL,
    semester_id INT NOT NULL,
    enrollment_date DATE NOT NULL,
    PRIMARY KEY (student_id, semester_id),
    FOREIGN KEY (student_id) REFERENCES students(student_id),
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id)
);

-- 2. EXAMINATION AND QUESTION BANK
CREATE TABLE examinations (
    exam_id INT AUTO_INCREMENT PRIMARY KEY,
    subject_id INT NOT NULL,
    semester_id INT NOT NULL,
    exam_title VARCHAR(150) NOT NULL,
    exam_type ENUM('QUIZ','MIDTERM','ENDTERM','PRACTICAL') NOT NULL,
    start_time DATETIME NOT NULL,
    end_time DATETIME NOT NULL,
    duration_minutes SMALLINT NOT NULL,
    total_marks DECIMAL(7,2) NOT NULL,
    pass_marks DECIMAL(7,2) NOT NULL,
    exam_status ENUM('SCHEDULED','OPEN','CLOSED','PUBLISHED') DEFAULT 'SCHEDULED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
    FOREIGN KEY (semester_id) REFERENCES semesters(semester_id),
    CHECK (end_time > start_time),
    CHECK (duration_minutes > 0),
    CHECK (total_marks > 0 AND pass_marks >= 0 AND pass_marks <= total_marks)
);

CREATE TABLE questions (
    question_id INT AUTO_INCREMENT PRIMARY KEY,
    subject_id INT NOT NULL,
    question_text TEXT NOT NULL,
    question_type ENUM('MCQ') NOT NULL DEFAULT 'MCQ',
    difficulty ENUM('EASY','MEDIUM','HARD') DEFAULT 'MEDIUM',
    marks DECIMAL(6,2) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (subject_id) REFERENCES subjects(subject_id),
    CHECK (marks > 0)
);

CREATE TABLE question_options (
    option_id INT AUTO_INCREMENT PRIMARY KEY,
    question_id INT NOT NULL,
    option_label CHAR(1) NOT NULL,
    option_text VARCHAR(500) NOT NULL,
    is_correct BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (question_id, option_label),
    FOREIGN KEY (question_id) REFERENCES questions(question_id) ON DELETE CASCADE
);

CREATE TABLE exam_questions (
    exam_id INT NOT NULL,
    question_id INT NOT NULL,
    question_order SMALLINT NOT NULL,
    marks DECIMAL(6,2) NOT NULL,
    PRIMARY KEY (exam_id, question_id),
    UNIQUE (exam_id, question_order),
    FOREIGN KEY (exam_id) REFERENCES examinations(exam_id) ON DELETE CASCADE,
    FOREIGN KEY (question_id) REFERENCES questions(question_id),
    CHECK (marks > 0)
);

-- 3. REGISTRATION, RESPONSES AND RESULTS
CREATE TABLE exam_registrations (
    registration_id INT AUTO_INCREMENT PRIMARY KEY,
    exam_id INT NOT NULL,
    student_id INT NOT NULL,
    registered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    registration_status ENUM('REGISTERED','WITHDRAWN','COMPLETED') DEFAULT 'REGISTERED',
    UNIQUE (exam_id, student_id),
    FOREIGN KEY (exam_id) REFERENCES examinations(exam_id),
    FOREIGN KEY (student_id) REFERENCES students(student_id)
);

CREATE TABLE responses (
    response_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    exam_id INT NOT NULL,
    student_id INT NOT NULL,
    question_id INT NOT NULL,
    selected_option_id INT NULL,
    answered_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (exam_id, student_id, question_id),
    FOREIGN KEY (exam_id, student_id)
        REFERENCES exam_registrations(exam_id, student_id),
    FOREIGN KEY (exam_id, question_id)
        REFERENCES exam_questions(exam_id, question_id),
    FOREIGN KEY (selected_option_id) REFERENCES question_options(option_id)
);

CREATE TABLE results (
    result_id INT AUTO_INCREMENT PRIMARY KEY,
    exam_id INT NOT NULL,
    student_id INT NOT NULL,
    marks_obtained DECIMAL(7,2) NOT NULL DEFAULT 0,
    total_marks DECIMAL(7,2) NOT NULL,
    percentage DECIMAL(5,2) NOT NULL DEFAULT 0,
    result_status ENUM('PASS','FAIL') NOT NULL,
    evaluated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (exam_id, student_id),
    FOREIGN KEY (exam_id) REFERENCES examinations(exam_id),
    FOREIGN KEY (student_id) REFERENCES students(student_id),
    CHECK (marks_obtained >= 0 AND marks_obtained <= total_marks),
    CHECK (percentage BETWEEN 0 AND 100)
);

-- 4. INDEXES FOR COMMON SEARCH AND REPORTING OPERATIONS
CREATE INDEX idx_exam_subject_schedule ON examinations(subject_id, start_time);
CREATE INDEX idx_exam_semester ON examinations(semester_id);
CREATE INDEX idx_question_subject_difficulty ON questions(subject_id, difficulty);
CREATE INDEX idx_registration_student ON exam_registrations(student_id, exam_id);
CREATE INDEX idx_response_student_exam ON responses(student_id, exam_id);
CREATE INDEX idx_result_exam_marks ON results(exam_id, marks_obtained DESC);

-- 5. AUTOMATED RESULT PROCESSING
DELIMITER //
CREATE PROCEDURE calculate_exam_result(IN p_exam_id INT, IN p_student_id INT)
BEGIN
    DECLARE v_total DECIMAL(7,2);
    DECLARE v_pass DECIMAL(7,2);
    DECLARE v_obtained DECIMAL(7,2) DEFAULT 0;
    DECLARE v_percentage DECIMAL(5,2) DEFAULT 0;

    IF NOT EXISTS (
        SELECT 1 FROM exam_registrations
        WHERE exam_id = p_exam_id AND student_id = p_student_id
          AND registration_status <> 'WITHDRAWN'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Student is not registered for this examination';
    END IF;

    SELECT total_marks, pass_marks INTO v_total, v_pass
    FROM examinations WHERE exam_id = p_exam_id;

    SELECT COALESCE(SUM(eq.marks), 0) INTO v_obtained
    FROM exam_questions eq
    JOIN responses r
      ON r.exam_id = eq.exam_id
     AND r.question_id = eq.question_id
     AND r.student_id = p_student_id
    JOIN question_options qo
      ON qo.option_id = r.selected_option_id
     AND qo.question_id = r.question_id
     AND qo.is_correct = TRUE
    WHERE eq.exam_id = p_exam_id;

    SET v_percentage = ROUND((v_obtained / v_total) * 100, 2);

    INSERT INTO results
        (exam_id, student_id, marks_obtained, total_marks, percentage, result_status)
    VALUES
        (p_exam_id, p_student_id, v_obtained, v_total, v_percentage,
         IF(v_obtained >= v_pass, 'PASS', 'FAIL'))
    ON DUPLICATE KEY UPDATE
        marks_obtained = VALUES(marks_obtained),
        total_marks = VALUES(total_marks),
        percentage = VALUES(percentage),
        result_status = VALUES(result_status),
        evaluated_at = CURRENT_TIMESTAMP;
END//
DELIMITER ;

DELIMITER //
CREATE PROCEDURE calculate_all_exam_results(IN p_exam_id INT)
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_student_id INT;
    DECLARE cur CURSOR FOR
        SELECT student_id FROM exam_registrations
        WHERE exam_id = p_exam_id AND registration_status <> 'WITHDRAWN';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;
    result_loop: LOOP
        FETCH cur INTO v_student_id;
        IF done THEN LEAVE result_loop; END IF;
        CALL calculate_exam_result(p_exam_id, v_student_id);
    END LOOP;
    CLOSE cur;
END//
DELIMITER ;

-- 6. SAMPLE DATA
INSERT INTO departments(department_name) VALUES
('Computer Science and Engineering'), ('Electronics and Communication');

INSERT INTO semesters(semester_number, academic_year) VALUES
(3, '2026-2027'), (4, '2026-2027');

INSERT INTO students(enrollment_no, first_name, last_name, email, department_id, admission_date) VALUES
('CSE26001','Aarav','Sharma','aarav@example.edu',1,'2025-08-01'),
('CSE26002','Diya','Verma','diya@example.edu',1,'2025-08-01'),
('CSE26003','Kabir','Singh','kabir@example.edu',1,'2025-08-01'),
('ECE26001','Meera','Rao','meera@example.edu',2,'2025-08-01');

INSERT INTO subjects(subject_code, subject_name, department_id, credits) VALUES
('CSE301','Database Management Systems',1,4),
('CSE302','Data Structures and Algorithms',1,4),
('ECE301','Digital Electronics',2,3);

INSERT INTO student_semesters(student_id, semester_id, enrollment_date) VALUES
(1,1,'2026-08-01'),(2,1,'2026-08-01'),(3,1,'2026-08-01'),(4,1,'2026-08-01');

INSERT INTO examinations(subject_id, semester_id, exam_title, exam_type, start_time, end_time,
                         duration_minutes, total_marks, pass_marks, exam_status) VALUES
(1,1,'DBMS Unit Test 1','QUIZ','2026-11-20 10:00:00','2026-11-20 11:00:00',60,30,12,'CLOSED'),
(2,1,'DSA Midterm','MIDTERM','2026-11-22 10:00:00','2026-11-22 12:00:00',120,50,20,'SCHEDULED');

INSERT INTO questions(subject_id, question_text, difficulty, marks) VALUES
(1,'Which SQL command is used to retrieve data from a table?','EASY',10),
(1,'Which normal form removes partial dependency?','MEDIUM',10),
(1,'Which key uniquely identifies each row in a relation?','EASY',10),
(2,'Which data structure follows LIFO order?','EASY',10);

INSERT INTO question_options(question_id, option_label, option_text, is_correct) VALUES
(1,'A','INSERT',FALSE),(1,'B','SELECT',TRUE),(1,'C','UPDATE',FALSE),(1,'D','DELETE',FALSE),
(2,'A','1NF',FALSE),(2,'B','2NF',TRUE),(2,'C','3NF',FALSE),(2,'D','BCNF',FALSE),
(3,'A','Foreign key',FALSE),(3,'B','Primary key',TRUE),(3,'C','Candidate attribute',FALSE),(3,'D','View',FALSE),
(4,'A','Queue',FALSE),(4,'B','Stack',TRUE),(4,'C','Tree',FALSE),(4,'D','Graph',FALSE);

INSERT INTO exam_questions(exam_id, question_id, question_order, marks) VALUES
(1,1,1,10),(1,2,2,10),(1,3,3,10),(2,4,1,10);

INSERT INTO exam_registrations(exam_id, student_id) VALUES
(1,1),(1,2),(1,3),(2,1),(2,2);

-- Student 1 gets all 3 right; student 2 gets 2 right; student 3 gets 1 right.
INSERT INTO responses(exam_id, student_id, question_id, selected_option_id) VALUES
(1,1,1,2),(1,1,2,6),(1,1,3,10),
(1,2,1,2),(1,2,2,5),(1,2,3,10),
(1,3,1,1),(1,3,2,6),(1,3,3,9);

-- Process results for all registered students in exam 1.
CALL calculate_all_exam_results(1);

-- 7. VIEWS
CREATE VIEW vw_student_exam_results AS
SELECT s.enrollment_no, CONCAT(s.first_name,' ',COALESCE(s.last_name,'')) AS student_name,
       sub.subject_code, sub.subject_name, e.exam_title, e.exam_type,
       r.marks_obtained, r.total_marks, r.percentage, r.result_status, r.evaluated_at
FROM results r
JOIN students s ON s.student_id = r.student_id
JOIN examinations e ON e.exam_id = r.exam_id
JOIN subjects sub ON sub.subject_id = e.subject_id;

CREATE VIEW vw_subject_performance AS
SELECT sub.subject_code, sub.subject_name, e.exam_title,
       COUNT(r.result_id) AS students_evaluated,
       ROUND(AVG(r.percentage),2) AS average_percentage,
       MAX(r.percentage) AS highest_percentage,
       MIN(r.percentage) AS lowest_percentage,
       SUM(r.result_status='PASS') AS pass_count,
       SUM(r.result_status='FAIL') AS fail_count
FROM examinations e
JOIN subjects sub ON sub.subject_id = e.subject_id
LEFT JOIN results r ON r.exam_id = e.exam_id
GROUP BY sub.subject_code, sub.subject_name, e.exam_id, e.exam_title;

-- 8. REQUIRED DEMONSTRATION QUERIES
-- Q1: Student-wise results with subject and examination details.
SELECT * FROM vw_student_exam_results ORDER BY subject_code, percentage DESC;

-- Q2: Subject-wise performance analytics.
SELECT * FROM vw_subject_performance ORDER BY subject_code;

-- Q3: INNER JOIN - students registered for each exam.
SELECT e.exam_title, s.enrollment_no, s.first_name, s.last_name
FROM exam_registrations er
INNER JOIN examinations e ON e.exam_id = er.exam_id
INNER JOIN students s ON s.student_id = er.student_id
ORDER BY e.exam_id, s.enrollment_no;

-- Q4: LEFT JOIN - include students even if they have no result yet.
SELECT s.enrollment_no, s.first_name, r.exam_id, r.percentage
FROM students s
LEFT JOIN results r ON r.student_id = s.student_id
ORDER BY s.enrollment_no;

-- Q5: SELF JOIN - compare students in the same department.
SELECT s1.enrollment_no AS student_1, s2.enrollment_no AS student_2,
       d.department_name
FROM students s1
JOIN students s2 ON s1.department_id = s2.department_id
                AND s1.student_id < s2.student_id
JOIN departments d ON d.department_id = s1.department_id;

-- Q6: Subquery - students scoring above the overall average.
SELECT s.enrollment_no, s.first_name, r.percentage
FROM students s JOIN results r ON r.student_id = s.student_id
WHERE r.percentage > (SELECT AVG(percentage) FROM results);

-- Q7: Correlated subquery - highest scorer(s) in each exam.
SELECT s.enrollment_no, s.first_name, r.exam_id, r.percentage
FROM results r JOIN students s ON s.student_id = r.student_id
WHERE r.percentage = (
    SELECT MAX(r2.percentage) FROM results r2 WHERE r2.exam_id = r.exam_id
);

-- Q8: UNION - student IDs appearing in either registrations or results.
SELECT student_id FROM exam_registrations
UNION
SELECT student_id FROM results;

-- Q9: INTERSECT equivalent using INNER JOIN (works on MySQL versions without INTERSECT).
SELECT DISTINCT er.student_id
FROM exam_registrations er
INNER JOIN results r
  ON r.student_id = er.student_id AND r.exam_id = er.exam_id;

-- Q10: EXCEPT equivalent using LEFT JOIN (registered students without a result).
SELECT DISTINCT er.student_id
FROM exam_registrations er
LEFT JOIN results r
  ON r.student_id = er.student_id AND r.exam_id = er.exam_id
WHERE r.result_id IS NULL;

-- Q11: Window function - rank students within each examination (MySQL 8.0+).
SELECT exam_id, student_id, marks_obtained, percentage,
       RANK() OVER (PARTITION BY exam_id ORDER BY percentage DESC) AS exam_rank,
       DENSE_RANK() OVER (PARTITION BY exam_id ORDER BY percentage DESC) AS dense_rank_position
FROM results;

-- Q12: CTE - semester-wise student performance.
WITH semester_scores AS (
    SELECT s.student_id, s.enrollment_no, ss.semester_id,
           AVG(r.percentage) AS average_percentage
    FROM students s
    JOIN student_semesters ss ON ss.student_id = s.student_id
    JOIN exam_registrations er ON er.student_id = s.student_id
    JOIN examinations e ON e.exam_id = er.exam_id AND e.semester_id = ss.semester_id
    LEFT JOIN results r ON r.exam_id = e.exam_id AND r.student_id = s.student_id
    GROUP BY s.student_id, s.enrollment_no, ss.semester_id
)
SELECT *, RANK() OVER (PARTITION BY semester_id ORDER BY average_percentage DESC) AS semester_rank
FROM semester_scores;

-- Q13: Questions with correct-answer counts.
SELECT q.question_id, q.question_text,
       COUNT(r.response_id) AS total_responses,
       SUM(qo.is_correct) AS correct_responses
FROM questions q
LEFT JOIN responses r ON r.question_id = q.question_id
LEFT JOIN question_options qo ON qo.option_id = r.selected_option_id
GROUP BY q.question_id, q.question_text;

-- Q14: Scheduled exams in the future.
SELECT exam_title, start_time, end_time, duration_minutes
FROM examinations
WHERE exam_status = 'SCHEDULED' AND start_time > NOW()
ORDER BY start_time;

-- 9. DML + TCL TRANSACTION EXAMPLE
START TRANSACTION;
INSERT INTO exam_registrations(exam_id, student_id) VALUES (2,3);
-- If the registration is valid, COMMIT; use ROLLBACK instead to undo it.
COMMIT;

-- 10. DCL EXAMPLE (run only with an account permitted to create users)
-- CREATE USER 'exam_readonly'@'localhost' IDENTIFIED BY 'ChangeThisStrongPassword!';
-- GRANT SELECT ON online_exam_system.* TO 'exam_readonly'@'localhost';
-- REVOKE SELECT ON online_exam_system.* FROM 'exam_readonly'@'localhost';

-- 11. VALIDATION / TEST QUERIES
SELECT COUNT(*) AS total_students FROM students;
SELECT COUNT(*) AS total_exams FROM examinations;
SELECT COUNT(*) AS total_questions FROM questions;
SELECT COUNT(*) AS generated_results FROM results;
SELECT * FROM results ORDER BY exam_id, marks_obtained DESC;

-- END OF PROJECT
