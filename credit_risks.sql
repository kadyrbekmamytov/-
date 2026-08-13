C:\Users\KADYRBEK\AppData\Roaming\DBeaverData\workspace6\General\Scripts\Credit_risks.sql


--- Общая статистика портфеля	
SELECT
    COUNT(*) AS total_loans, --- общее количество выданных займов 
    SUM(loan_status) AS total_defaults, --- количество дефолтов
    COUNT(*) - SUM(loan_status) AS total_paid, --- количество погашенных займов
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate_pct,
    ROUND(AVG(loan_amnt), 0) AS avg_loan_amount, --- средняя сумма займов
    ROUND(SUM(loan_amnt) / 1000000.0, 2) AS total_portfolio_mln, --- общий объем выданных денег
    ROUND(AVG(person_income), 0) AS avg_borrower_income --- средний доход заемщиков
FROM loans;


--- Дефолты по кредитному рейтингу
SELECT
    loan_grade,
    COUNT(*) AS total,
    SUM(loan_status) AS defaults,
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2)  AS default_rate,
    ROUND(AVG(loan_int_rate), 2) AS avg_interest_rate, --- средняя ставка
    ROUND(AVG(loan_amnt), 0)  AS avg_loan_amount
FROM loans l
GROUP BY loan_grade
ORDER BY loan_grade;


--- Дефолты по целям займа, чтобы узнать на какие цели больше всего риск
SELECT
    loan_intent, --- цель займа
    COUNT(*) AS total,
    SUM(loan_status) AS defaults,
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate,
    ROUND(AVG(loan_amnt), 0) AS avg_loan
FROM loans
GROUP BY loan_intent
ORDER BY default_rate DESC;


--- Разделение по возрасту
SELECT
	CASE 
		WHEN person_age < 25 THEN '18-24'
		WHEN person_age < 35 THEN '25-34'
		WHEN person_age < 45 THEN '35-44'
		WHEN person_age < 55 THEN '45-54'
		ELSE '55+'
	END AS age_group,
	COUNT(*) AS total,
	SUM(loan_status) AS defaults ,
	ROUND(SUM(loan_status)*100.0 / COUNT(*), 2) AS default_rate,
	ROUND(AVG(person_income), 0 ) AS avg_income,
	ROUND(AVG(loan_amnt), 0 ) AS avg_loan
FROM loans  
WHERE person_age <= 80 --- это нужно для того чтобы исключить возраст такой как 144
GROUP BY age_group
ORDER BY age_group;


---Разделение по доходу
SELECT
    income_segment,
    COUNT(*) AS total,
    SUM(loan_status) AS defaults,
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate,
    ROUND(AVG(loan_percent_income), 3) AS avg_loan_to_income --- средняя доля займа в доходе
FROM (
    SELECT
        loan_status, loan_percent_income,
        CASE
            WHEN person_income < 30000  THEN '1. Low (<$30K)'
            WHEN person_income < 60000  THEN '2. Middle ($30K-60K)'
            WHEN person_income < 100000 THEN '3. High ($60K-100K)'
            ELSE                             '4. Very High ($100K+)'
        END AS income_segment
    FROM loans
)
GROUP BY income_segment
ORDER BY income_segment;

---Есть ли связь между рейтингом и типом жилья
SELECT
    loan_grade,
    person_home_ownership,
    COUNT(*) AS total,
    SUM(loan_status) AS defaults,
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate
FROM loans
GROUP BY loan_grade, person_home_ownership
HAVING COUNT(*) >= 30
ORDER BY default_rate DESC
LIMIT 15;

---Влияние прошлых заемов
SELECT
    cb_person_default_on_file AS hist_default, 
    loan_grade,
    COUNT(*) AS total,
    ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate,
    ROUND(AVG(loan_int_rate), 2) AS avg_rate,
    ROUND(AVG(cb_person_cred_hist_length), 1) AS avg_credit_hist_years
FROM loans
WHERE loan_int_rate IS NOT NULL
GROUP BY cb_person_default_on_file, loan_grade
ORDER BY cb_person_default_on_file, loan_grade;

--- Ранжирование заемщиков
SELECT
    person_age,
    person_income,
    loan_grade,
    loan_amnt,
    loan_int_rate,
    loan_status,
    RANK() OVER (PARTITION BY loan_grade ORDER BY loan_int_rate DESC) AS rate_rank_in_grade,
    AVG(loan_int_rate) OVER (PARTITION BY loan_grade) AS avg_rate_in_grade,
    AVG(loan_int_rate) OVER () AS overall_avg_rate,
    ROW_NUMBER()   OVER (PARTITION BY loan_grade, loan_status ORDER BY loan_amnt DESC) AS row_num
FROM loans
WHERE loan_int_rate IS NOT NULL --- процентная ставка
ORDER BY loan_grade, rate_rank_in_grade
LIMIT 100;

---Этот запрос комбинирует показатели и дает оценку 
WITH risk_profiles AS (
    SELECT
        loan_grade,
        loan_intent,
        person_home_ownership,
        COUNT(*) AS total,
        SUM(loan_status) AS defaults,
        ROUND(SUM(loan_status) * 100.0 / COUNT(*), 2) AS default_rate,
        ROUND(AVG(loan_amnt), 0) AS avg_loan,
        ROUND(AVG(loan_int_rate), 2) AS avg_rate
    FROM loans
    WHERE loan_int_rate IS NOT NULL
    GROUP BY loan_grade, loan_intent, person_home_ownership
    HAVING COUNT(*) >= 30
),
ranked AS (
    SELECT *,
           RANK() OVER (ORDER BY default_rate DESC) AS risk_rank
    FROM risk_profiles
)
SELECT * 
FROM ranked
WHERE default_rate > 40
ORDER BY risk_rank
LIMIT 20;

---Потери от дефолтов
SELECT
    loan_grade,
    COUNT(*)  AS total_loans,
    SUM(loan_status) AS defaults,
    SUM(CASE WHEN loan_status = 1 THEN loan_amnt ELSE 0 END) AS loss,
    SUM(loan_amnt) AS total_portfolio,
    ROUND(SUM(CASE WHEN loan_status = 1 THEN loan_amnt ELSE 0 END) * 100.0 / SUM(loan_amnt),2) AS loss_pct_of_portfolio
FROM loans
GROUP BY loan_grade
ORDER BY loan_grade;
