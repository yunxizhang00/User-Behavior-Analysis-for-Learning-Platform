use customer_engagement;

-- Find total number of students.
SELECT COUNT(distinct student_id)
FROM student_engagement;
-- result: 19332

-- 1. Using information from student purchase table to retrieve id of the purchase, id of the student who made the purchase, purchase type, purchase date which marks the start date of student subscription, the date on which the subscription ends and refund date.
CREATE VIEW purchases_info AS
SELECT 
    purchase_id,
    student_id,
    purchase_type,
    date_start,
    IF(date_refunded IS NULL,
        date_end,
        date_refunded) AS date_end
FROM
    (SELECT 
        purchase_id,
            student_id,
            purchase_type,
            date_purchased AS date_start,
            CASE
                WHEN purchase_type = 0 THEN DATE_ADD(MAKEDATE(YEAR(date_purchased), DAY(date_purchased)), INTERVAL MONTH(date_purchased) MONTH)
                WHEN purchase_type = 1 THEN DATE_ADD(MAKEDATE(YEAR(date_purchased), DAY(date_purchased)), INTERVAL MONTH(date_purchased) + 2 MONTH)
                WHEN purchase_type = 2 THEN DATE_ADD(MAKEDATE(YEAR(date_purchased), DAY(date_purchased)), INTERVAL MONTH(date_purchased) + 11 MONTH)
            END AS date_end,
            date_refunded
    FROM
        student_purchases) a;

-- 2. Finding out each student's learning time (watched minutes) and payment status on each viewing date.
SELECT c.* FROM
(
SELECT 
    student_id,
    date_watched,
    SUM(minutes_watched) AS minutes_watched,
    paid
FROM
    (SELECT 
        student_id, date_watched, minutes_watched, MAX(paid) AS paid
    FROM
        (SELECT 
        l.student_id,
            l.date_watched,
            l.minutes_watched,
            p.date_start,
            p.date_end,
            CASE
                WHEN date_start IS NULL AND date_end IS NULL THEN 0
                WHEN date_watched BETWEEN date_start AND date_end THEN 1
                WHEN date_watched NOT BETWEEN date_start AND date_end THEN 0
            END AS paid
    FROM
        student_learning l
    LEFT JOIN purchases_info p USING (student_id)) a
    GROUP BY student_id , date_watched) b 
    GROUP BY student_id, date_watched) c;
    
-- 3. Classifying students as onboarded or not onboarded.
SELECT 
    *, 0 AS student_onboarded
FROM
    student_info
WHERE
    student_id NOT IN (SELECT DISTINCT
            student_id
        FROM
            student_engagement) 
UNION SELECT 
    *, 1 AS student_onboarded
FROM
    student_info
WHERE
    student_id IN (SELECT DISTINCT
            student_id
        FROM
            student_engagement);

-- 4. Analyzing students’ engagement records and purchase behaviors.
SELECT 
    student_id, date_engaged, MAX(paid) AS paid
FROM
    (SELECT 
        e.student_id,
            e.date_engaged,
            p.date_start,
            p.date_end,
            CASE
                WHEN date_start IS NULL AND date_end IS NULL THEN 0
                WHEN date_engaged BETWEEN date_start AND date_end THEN 1
                WHEN date_engaged NOT BETWEEN date_start AND date_end THEN 0
            END AS paid
    FROM
        student_engagement e
    LEFT JOIN purchases_info p USING (student_id)) a
GROUP BY student_id , date_engaged;

-- 5. Analyzing course information.
-- 5.1 Calculating the total watching minutes for each course.
-- 5.2 Calculating the average student watching time.
-- 5.3 Calculating the course completion rate for each course.
SELECT 
    course_id,
    course_title,
    minutes_watched,
    ROUND(minutes_watched / students_watched, 2) AS minutes_per_student,
    ROUND((minutes_watched / students_watched) / course_duration,
            2) AS completion_rate
FROM
    (SELECT 
    i.*,
    ROUND(SUM(l.minutes_watched), 2) AS minutes_watched,
    COUNT(DISTINCT l.student_id) AS students_watched
FROM
    course_info i
        JOIN
    student_learning l USING (course_id)
GROUP BY course_id) a;

-- 6. Analyzing course ratings.
SELECT 
    course_rating
FROM
    course_ratings;

-- 7. Finding the student's exam records.
SELECT 
    e.exam_attempt_id,
    e.student_id,
    e.exam_id,
    i.exam_category,
    exam_passed,
    e.date_exam_completed AS date_exam_completed
FROM
    student_exams e
    join exam_info i using(exam_id);

-- 8. Analyzing students’ purchase status at the certificate issued date and marking them.
SELECT 
    certificate_id, student_id, certificate_type, date_issued, MAX(paid) AS paid
FROM
    (SELECT 
        c.certificate_id,
            c.student_id,
            c.certificate_type,
            c.date_issued,
            p.date_start,
            p.date_end,
            CASE
                WHEN date_start IS NULL AND date_end IS NULL THEN 0
                WHEN date_issued BETWEEN date_start AND date_end THEN 1
                WHEN date_issued NOT BETWEEN date_start AND date_end THEN 0
            END AS paid
    FROM
        student_certificates c
    LEFT JOIN purchases_info p USING (student_id)) a
GROUP BY certificate_id;

-- 9. Analyzing student behavior in career tracks.
with table_course_exams as
(
SELECT DISTINCT
    se.student_id, e.course_id
FROM
    student_exams se
        JOIN
    exam_info e USING (exam_id)
WHERE
    e.exam_category = 2
),
table_course_certificates as
(
SELECT DISTINCT
    student_id, course_id
FROM
    student_certificates
WHERE
    certificate_type = 1
),
table_attempted_course_exam_certificate_issued as
(
SELECT 
    student_id,
    enrolled_in_track_id,
    MAX(attempted_course_exam) AS attempted_course_exam,
    MAX(certificate_course_id) as certificate_course_id
FROM
(-- Finding the successful course exams.
SELECT 
    c.*,
    CASE
        WHEN cc.course_id IS NULL THEN 0
        WHEN
            cc.course_id IS NOT NULL
                AND c.attempted_course_exam = 0
        THEN
            0
        WHEN
            cc.course_id IS NOT NULL
                AND c.attempted_course_exam = 1
        THEN
            1
    END AS certificate_course_id
    FROM
( -- Finding the enrollment in track and the attempted_course_exam column.
SELECT 
        a.student_id,
            a.track_id as enrolled_in_track_id,
            a.course_id,
            b.track_id,
            CASE
                WHEN a.course_id IS NULL THEN 0
                WHEN
                    a.course_id IS NOT NULL
                        AND b.track_id IS NULL
                THEN
                    0
                WHEN
                    a.course_id IS NOT NULL
                        AND b.track_id IS NOT NULL
                THEN
                    1
            END AS attempted_course_exam
    FROM
        (-- Finding the course id's of the course exams that a student has attempted.
        SELECT DISTINCT
    *
FROM
    student_career_track_enrollments en
        LEFT JOIN
    table_course_exams ex USING (student_id)
ORDER BY student_id , track_id , course_id) a
    LEFT JOIN career_track_info b ON a.track_id = b.track_id
        AND a.course_id = b.course_id) c
	LEFT JOIN table_course_certificates cc ON c.student_id = cc.student_id
	AND c.course_id = cc.course_id ) d
GROUP BY student_id , enrolled_in_track_id
),
table_track_exams as
(
SELECT DISTINCT
    se.student_id, e.track_id
FROM
    student_exams se
        JOIN
    exam_info e USING (exam_id)
WHERE
    e.exam_category = 3
),
table_attempted_final_exam as
(
SELECT DISTINCT
    i.*, ex.track_id AS attempted_track_id
FROM
    table_attempted_course_exam_certificate_issued i
        LEFT JOIN
    table_track_exams ex ON i.student_id = ex.student_id
        AND i.enrolled_in_track_id = ex.track_id
),
table_certificates as
(
SELECT 
    student_id, track_id, cast(date_issued as date) as date_issued
FROM
    student_certificates
WHERE
    certificate_type = 2
),
table_issued_certificates as
(
SELECT DISTINCT
    e.*, c.track_id as certificate_track_id, c.date_issued
FROM
    table_attempted_final_exam e
    LEFT JOIN
    table_certificates c
    ON e.student_id = c.student_id
        AND e.enrolled_in_track_id = c.track_id
),
table_final as
(
SELECT 
    enrolled_in_track_id AS track_id,
    COUNT(enrolled_in_track_id) AS enrolled_in_track_id,
    SUM(attempted_course_exam) AS attempted_course_exam,
    SUM(certificate_course_id) AS certificate_course_id,
    COUNT(attempted_track_id) AS attempted_track_id,
    COUNT(certificate_track_id) AS certificate_track_id
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
),
table_reordered as
(
SELECT 
    'Enrolled in a track' AS 'action',
    enrolled_in_track_id AS 'track',
    COUNT(enrolled_in_track_id) AS 'count'
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
UNION
SELECT 
    'Attempted a course exam' AS 'action',
    enrolled_in_track_id AS 'track',
    SUM(attempted_course_exam) AS 'count'
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
UNION
SELECT 
    'Completed a course exam' AS 'action',
    enrolled_in_track_id AS 'track',
    SUM(certificate_course_id) AS 'count'
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
UNION
SELECT 
    'Attempted a final exam' AS 'action',
    enrolled_in_track_id AS 'track',
    COUNT(attempted_track_id) AS 'count'
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
UNION
SELECT 
    'Earned a career track certificate' AS 'action',
    enrolled_in_track_id AS 'track',
    COUNT(certificate_track_id) AS 'count'
FROM
    table_issued_certificates
GROUP BY enrolled_in_track_id
)
select * from table_reordered;

-- 10. Analyzing students’ learning behavior within buckets.
with table_period_to_consider as
(
SELECT 
    i.student_id,
    i.date_registered,
    0 as paid,
    '2022-10-31' AS last_date_to_watch
FROM
    student_info i
        LEFT JOIN
    student_purchases p USING (student_id)
WHERE
    p.student_id IS NULL

UNION

SELECT 
    i.student_id,
    i.date_registered,
    1 as paid,
    MIN(date_purchased) AS last_date_to_watch
FROM
    student_info i
        JOIN
    student_purchases p USING (student_id)
GROUP BY p.student_id
),
table_minutes_summed_1 as
(
SELECT 
    p.*,
    0 AS total_minutes_watched
FROM
    table_period_to_consider p
        LEFT JOIN
    student_learning l using(student_id)
WHERE
    l.student_id is null
    
UNION

SELECT 
    p.*,
    ROUND(SUM(l.minutes_watched), 2) AS total_minutes_watched
FROM
    table_period_to_consider p
        JOIN
    student_learning l using(student_id)
WHERE
    l.date_watched BETWEEN p.date_registered AND p.last_date_to_watch
GROUP BY l.student_id
),
table_minutes_summed_2 as
(
SELECT 
    *
FROM
    table_minutes_summed_1

UNION

SELECT 
    p.*, 0 AS total_minutes_watched
FROM
    table_period_to_consider p
        JOIN
    student_learning l USING (student_id)
WHERE
    l.date_watched NOT BETWEEN p.date_registered AND p.last_date_to_watch
        AND l.student_id NOT IN (SELECT 
            student_id
        FROM
            table_minutes_summed_1)
GROUP BY l.student_id
),
table_distribute_to_buckets as
(
SELECT 
    *,
    CASE
        WHEN
            total_minutes_watched = 0
                OR total_minutes_watched IS NULL
        THEN
            '[0]'
        WHEN
            total_minutes_watched > 0
                AND total_minutes_watched <= 5
        THEN
            '(0, 5]'
        WHEN
            total_minutes_watched > 5
                AND total_minutes_watched <= 10
        THEN
            '(5, 10]'
        WHEN
            total_minutes_watched > 10
                AND total_minutes_watched <= 15
        THEN
            '(10, 15]'
        WHEN
            total_minutes_watched > 15
                AND total_minutes_watched <= 20
        THEN
            '(15, 20]'
        WHEN
            total_minutes_watched > 20
                AND total_minutes_watched <= 25
        THEN
            '(20, 25]'
        WHEN
            total_minutes_watched > 25
                AND total_minutes_watched <= 30
        THEN
            '(25, 30]'
        WHEN
            total_minutes_watched > 30
                AND total_minutes_watched <= 40
        THEN
            '(30, 40]'
        WHEN
            total_minutes_watched > 40
                AND total_minutes_watched <= 50
        THEN
            '(40, 50]'
        WHEN
            total_minutes_watched > 50
                AND total_minutes_watched <= 60
        THEN
            '(50, 60]'
        WHEN
            total_minutes_watched > 60
                AND total_minutes_watched <= 70
        THEN
            '(60, 70]'
        WHEN
            total_minutes_watched > 70
                AND total_minutes_watched <= 80
        THEN
            '(70, 80]'
        WHEN
            total_minutes_watched > 80
                AND total_minutes_watched <= 90
        THEN
            '(80, 90]'
        WHEN
            total_minutes_watched > 90
                AND total_minutes_watched <= 100
        THEN
            '(90, 100]'
        WHEN
            total_minutes_watched > 100
                AND total_minutes_watched <= 110
        THEN
            '(100, 110]'
        WHEN
            total_minutes_watched > 110
                AND total_minutes_watched <= 120
        THEN
            '(110, 120]'
        WHEN
            total_minutes_watched > 120
                AND total_minutes_watched <= 240
        THEN
            '(120, 240]'
        WHEN
            total_minutes_watched > 240
                AND total_minutes_watched <= 480
        THEN
            '(240, 480]'
        WHEN
            total_minutes_watched > 480
                AND total_minutes_watched <= 1000
        THEN
            '(480, 1000]'
        WHEN
            total_minutes_watched > 1000
                AND total_minutes_watched <= 2000
        THEN
            '(1000, 2000]'
        WHEN
            total_minutes_watched > 2000
                AND total_minutes_watched <= 3000
        THEN
            '(2000, 3000]'
        WHEN
            total_minutes_watched > 3000
                AND total_minutes_watched <= 4000
        THEN
            '(3000, 4000]'
        WHEN
            total_minutes_watched > 4000
                AND total_minutes_watched <= 6000
        THEN
            '(4000, 6000]'
        ELSE '6000+'
    END AS buckets
FROM
    table_minutes_summed_2
)
select  
student_id,
date_registered,
paid as f2p,
total_minutes_watched,
buckets
from table_distribute_to_buckets;

-- 11. Analyzing students’ paid learning behavior.
with table_paid_duration as
(
SELECT 
    student_id,
    MIN(date_start) AS first_paid_day,
    IF(MAX(date_end) <= '2022-10-31',
        MAX(date_end),
        '2022-10-31') AS last_paid_day
FROM
    purchases_info
GROUP BY student_id
),
table_content_watched_1 as
(
SELECT 
    d.*, ROUND(SUM(l.minutes_watched), 2) AS total_minutes_watched
FROM
    table_paid_duration d
        JOIN
    student_learning l USING (student_id)
WHERE
    date_watched BETWEEN first_paid_day AND last_paid_day
GROUP BY d.student_id

UNION

SELECT 
    d.*, 0 AS total_minutes_watched
FROM
    table_paid_duration d
        LEFT JOIN
    student_learning l USING (student_id)
WHERE
    l.student_id IS NULL
),
table_content_watched_2 as
(
SELECT 
    *
FROM
    table_content_watched_1

UNION 

SELECT 
    d.*, 0 AS total_minutes_watched
FROM
    table_paid_duration d
        JOIN
    student_learning l USING (student_id)
WHERE
    date_watched NOT BETWEEN first_paid_day AND last_paid_day
        AND l.student_id NOT IN (SELECT 
            student_id
        FROM
            table_content_watched_1)
),
table_duration_in_days as
(
SELECT 
    *,
    DATEDIFF(last_paid_day, first_paid_day) AS difference_in_days
FROM
    table_content_watched_2
),
table_distribute_to_buckets as
(
SELECT 
    d.*,
    i.date_registered,
    CASE
        WHEN
            total_minutes_watched = 0
                OR total_minutes_watched IS NULL
        THEN
            '[0]'
        WHEN
            total_minutes_watched > 0
                AND total_minutes_watched <= 30
        THEN
            '(0, 30]'
        WHEN
            total_minutes_watched > 30
                AND total_minutes_watched <= 60
        THEN
            '(30, 60]'
        WHEN
            total_minutes_watched > 60
                AND total_minutes_watched <= 120
        THEN
            '(60, 120]'
        WHEN
            total_minutes_watched > 120
                AND total_minutes_watched <= 240
        THEN
            '(120, 240]'
        WHEN
            total_minutes_watched > 240
                AND total_minutes_watched <= 480
        THEN
            '(240, 480]'
        WHEN
            total_minutes_watched > 480
                AND total_minutes_watched <= 1000
        THEN
            '(480, 1000]'
        WHEN
            total_minutes_watched > 1000
                AND total_minutes_watched <= 2000
        THEN
            '(1000, 2000]'
        WHEN
            total_minutes_watched > 2000
                AND total_minutes_watched <= 3000
        THEN
            '(2000, 3000]'
        WHEN
            total_minutes_watched > 3000
                AND total_minutes_watched <= 4000
        THEN
            '(3000, 4000]'
        WHEN
            total_minutes_watched > 4000
                AND total_minutes_watched <= 6000
        THEN
            '(4000, 6000]'
        ELSE '6000+'
        END AS user_buckets
FROM
    table_duration_in_days d
    join
    student_info i
    using(student_id)
)
SELECT 
    student_id,
    date_registered,
    total_minutes_watched,
    difference_in_days AS num_paid_days,
    user_buckets AS 'buckets'
FROM
    table_distribute_to_buckets;

