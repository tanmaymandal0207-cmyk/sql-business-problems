/* =============================================================================
   Case study · Gratuity liability under the new labour codes — validation checks
   Dialect : Google BigQuery Standard SQL
   Run after analysis.sql. Every row should return status = 'PASS'.
   ============================================================================= */

DECLARE val_date       DATE    DEFAULT DATE '2026-03-31';
DECLARE wage_share_old FLOAT64 DEFAULT 0.40;
DECLARE wage_share_new FLOAT64 DEFAULT 0.50;
DECLARE discount_rate  FLOAT64 DEFAULT 0.07;
DECLARE attrition      FLOAT64 DEFAULT 0.10;
DECLARE vesting_years  FLOAT64 DEFAULT 5;
DECLARE ceiling        FLOAT64 DEFAULT 2000000;
DECLARE entry_age      FLOAT64 DEFAULT 25;
DECLARE retire_age     FLOAT64 DEFAULT 60;

WITH e AS (SELECT * FROM `sahyadri_b2b.gr_employees`),
     a AS (SELECT * FROM `sahyadri_b2b.gr_accrued`),
     p AS (SELECT * FROM `sahyadri_b2b.gr_projection`),

per_employee AS (
    SELECT employee_id, SUM(exit_probability) AS total_probability, COUNT(*) AS exit_years, MAX(t) AS last_year,
           MAX(years_to_retirement) AS ytr
    FROM p GROUP BY employee_id
),

checks AS (
    SELECT '01. Employees = in service on 31 March 2026, salary missing flagged' AS check_name, 0 AS expected,
           ABS((SELECT COUNT(*) FROM e) - (SELECT COUNTIF(hire_date <= val_date) FROM `sahyadri_b2b.employees`))
         + ABS((SELECT COUNTIF(salary_missing) FROM e) - (SELECT COUNTIF(salary IS NULL AND hire_date <= val_date) FROM `sahyadri_b2b.employees`))
         + ABS((SELECT COUNT(*) FROM a) - (SELECT COUNTIF(NOT salary_missing) FROM e)) AS actual
    UNION ALL
    SELECT '02. Gratuity years = completed years, plus one if the part-year exceeds six months', 0,
           (SELECT COUNTIF(gratuity_years != FLOOR(service_years) + IF(service_years - FLOOR(service_years) > 0.5, 1, 0)
                        OR ABS(service_years - DATE_DIFF(val_date, hire_date, DAY) / 365.25) > 1e-9) FROM e)
    UNION ALL
    SELECT '03. Accrued = 15/26 x monthly wages x gratuity years from five years of service, zero before, never above Rs 20 lakh', 0,
           (SELECT COUNTIF(ABS(accrued_new_wages - IF(service_years >= vesting_years,
                                   LEAST(ceiling, 15 / 26 * annual_ctc * wage_share_new / 12 * gratuity_years), 0)) > 1e-6
                        OR accrued_new_wages > ceiling
                        OR (service_years < vesting_years AND (accrued_new_wages != 0 OR accrued_old_wages != 0))) FROM a)
    UNION ALL
    SELECT '04. Exit probabilities add up to 1 for every employee', 0,
           (SELECT COUNTIF(ABS(total_probability - 1) > 1e-9) FROM per_employee)
    UNION ALL
    SELECT '05. One exit year per future year up to retirement: rows = CEIL(years to retirement)', 0,
           (SELECT COUNTIF(exit_years != CEIL(ytr) OR last_year != CEIL(ytr)
                        OR ABS(ytr - ((retire_age - entry_age) - (SELECT service_years FROM e WHERE e.employee_id = per_employee.employee_id))) > 1e-9)
              FROM per_employee)
    UNION ALL
    SELECT '06. Attrition years: probability = 0.9^(t-1) x 0.1, retirement year takes the rest', 0,
           (SELECT COUNTIF(ABS(exit_probability - IF(t < CEIL(years_to_retirement),
                                                     POW(1 - attrition, t - 1) * attrition, POW(1 - attrition, t - 1))) > 1e-12) FROM p)
    UNION ALL
    SELECT '07. Service at exit = service today + t - 0.5, discount factor = 1.07^-(t-0.5)', 0,
           (SELECT COUNTIF(ABS(service_at_exit - (service_years + t - 0.5)) > 1e-9
                        OR ABS(discount_factor - POW(1 + discount_rate, -(t - 0.5))) > 1e-12) FROM p)
    UNION ALL
    SELECT '08. Vested at exit = five years of service at exit, gratuity years at exit rounded the same way', 0,
           (SELECT COUNTIF(vested_at_exit != (service_at_exit >= vesting_years)
                        OR gratuity_years_at_exit != FLOOR(service_at_exit) + IF(service_at_exit - FLOOR(service_at_exit) > 0.5, 1, 0)) FROM p)
    UNION ALL
    SELECT '09. With no one at the Rs 20 lakh cap, accrued at 50 % wages = 1.25 x accrued at 40 % wages', 0,
           IF((SELECT COUNTIF(accrued_new_wages >= ceiling) FROM a) = 0
              AND ABS((SELECT SUM(accrued_new_wages) - 1.25 * SUM(accrued_old_wages) FROM a)) > 1e-3, 1, 0)
    UNION ALL
    SELECT '10. Every valued employee is in the projection, and only they are', 0,
           ABS((SELECT COUNT(*) FROM per_employee) - (SELECT COUNT(*) FROM a))
         + (SELECT COUNT(*) FROM per_employee WHERE employee_id NOT IN (SELECT employee_id FROM a))
)

SELECT
    check_name,
    expected,
    actual,
    IF(actual = expected, 'PASS', 'FAIL') AS status
FROM checks
ORDER BY check_name;
