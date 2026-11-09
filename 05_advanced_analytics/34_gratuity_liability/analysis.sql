/* =============================================================================
   Case study · Gratuity liability under the new labour codes: a projected
   unit credit valuation in SQL, and what the 50 % wage rule adds
   Category : Advanced analytics
   Dataset  : sahyadri_b2b
   Dialect  : Google BigQuery Standard SQL (multi-statement script)

   BUSINESS PROBLEM
   The company has never provided for gratuity: it pays it from cash when
   someone leaves after five years. The auditor wants a provision at
   31 March 2026 measured the Ind AS 19 way (projected unit credit), and
   the labour codes in force since 21 November 2025 change the wage on
   which gratuity is calculated: allowances above half of total
   remuneration now count as wages. The CFO asks:
     1. What would the company owe if everyone left on 31 March 2026, on
        today's pay structure and under the 50 % wage rule?
     2. What is the actuarial obligation (DBO) and the cost of one more
        year of service, and how sensitive are they to the assumptions?
     3. Which departments and length-of-service groups carry it?
     4. How much cash should be set aside for gratuity paid next year?

   RULES APPLIED (as summarised by labour-law practitioners; see the README)
     - Gratuity = 15 / 26 x last drawn monthly wages x completed years of
       service; a final part-year of more than six months counts as a year.
     - Payable after five years of continuous service (one year for
       fixed-term employees; the company has none).
     - Ceiling Rs 20 lakh per employee.
     - From 21 November 2025, wages for gratuity must be at least 50 % of
       total remuneration.

   METHOD AND ASSUMPTIONS
     - Employees: in service on 31 March 2026 with a salary recorded;
       salary = annual cost to company. Two long-serving employees have no
       salary recorded and are reported separately.
     - Wages for gratuity: 40 % of CTC on the current pay structure
       (assumed), 50 % under the labour codes.
     - Actuarial assumptions (illustrative, to be replaced by the
       actuary's): discount rate 7.0 %, salary growth 8.0 % a year,
       attrition 10 % a year at all lengths of service, everyone joined at
       25 and retires at 60. Mortality is ignored.
     - Exits happen mid-year. Service at an exit in year t = service on
       31 March 2026 + t - 0.5; wages then = today's x (1 + growth)^(t - 1).
     - Projected unit credit: each projected benefit is attributed to past
       service in proportion (service today / service at exit), weighted by
       the chance of leaving in that year and discounted.
     - Current service cost: the benefit attributed to the next year of
       service, 1 / service at exit, on the same basis.
   ============================================================================= */

DECLARE val_date       DATE    DEFAULT DATE '2026-03-31';
DECLARE wage_share_old FLOAT64 DEFAULT 0.40;
DECLARE wage_share_new FLOAT64 DEFAULT 0.50;
DECLARE discount_rate  FLOAT64 DEFAULT 0.07;
DECLARE salary_growth  FLOAT64 DEFAULT 0.08;
DECLARE attrition      FLOAT64 DEFAULT 0.10;
DECLARE vesting_years  FLOAT64 DEFAULT 5;
DECLARE ceiling        FLOAT64 DEFAULT 2000000;
DECLARE entry_age      FLOAT64 DEFAULT 25;
DECLARE retire_age     FLOAT64 DEFAULT 60;

-- -----------------------------------------------------------------------------
-- Step 1 · Employees, accrued gratuity today, and the projected exits
-- -----------------------------------------------------------------------------
CREATE OR REPLACE TABLE `sahyadri_b2b.gr_employees` AS
SELECT e.employee_id, e.employee_name, e.designation, d.department_name, e.hire_date, e.salary AS annual_ctc,
       DATE_DIFF(val_date, e.hire_date, DAY) / 365.25                                AS service_years,
       -- completed years for gratuity: a final part-year over six months counts as a year
       FLOOR(DATE_DIFF(val_date, e.hire_date, DAY) / 365.25)
         + IF(DATE_DIFF(val_date, e.hire_date, DAY) / 365.25 - FLOOR(DATE_DIFF(val_date, e.hire_date, DAY) / 365.25) > 0.5, 1, 0) AS gratuity_years,
       e.salary IS NULL                                                               AS salary_missing
FROM `sahyadri_b2b.employees` AS e
JOIN `sahyadri_b2b.departments` AS d ON d.department_id = e.department_id
WHERE e.hire_date <= val_date;

CREATE OR REPLACE TABLE `sahyadri_b2b.gr_accrued` AS
SELECT employee_id, department_name, designation, service_years, gratuity_years, annual_ctc,
       IF(service_years >= vesting_years,
          LEAST(ceiling, 15 / 26 * annual_ctc * wage_share_old / 12 * gratuity_years), 0) AS accrued_old_wages,
       IF(service_years >= vesting_years,
          LEAST(ceiling, 15 / 26 * annual_ctc * wage_share_new / 12 * gratuity_years), 0) AS accrued_new_wages
FROM `sahyadri_b2b.gr_employees`
WHERE NOT salary_missing;

-- One row per employee and future year of possible exit, with three valuation bases
CREATE OR REPLACE TABLE `sahyadri_b2b.gr_projection` AS
WITH years AS (
    SELECT t FROM UNNEST(GENERATE_ARRAY(1, 35)) AS t
),
grid AS (
    SELECT e.employee_id, e.department_name, e.service_years, e.annual_ctc, y.t,
           e.service_years + y.t - 0.5                                                AS service_at_exit,
           -- years left to retirement, assuming everyone joined at 25
           (retire_age - entry_age) - e.service_years                                 AS years_to_retirement
    FROM `sahyadri_b2b.gr_employees` AS e
    CROSS JOIN years AS y
    WHERE NOT e.salary_missing
),
with_probability AS (
    SELECT g.*,
           CASE WHEN g.t < CEIL(g.years_to_retirement) THEN POW(1 - attrition, g.t - 1) * attrition
                -- the retirement year takes everyone still in service
                WHEN g.t = CEIL(g.years_to_retirement) THEN POW(1 - attrition, g.t - 1)
                ELSE 0 END                                                             AS exit_probability
    FROM grid AS g
)
SELECT p.*,
       FLOOR(p.service_at_exit) + IF(p.service_at_exit - FLOOR(p.service_at_exit) > 0.5, 1, 0) AS gratuity_years_at_exit,
       p.service_at_exit >= vesting_years                                             AS vested_at_exit,
       POW(1 + discount_rate, -(p.t - 0.5))                                           AS discount_factor
FROM with_probability AS p
WHERE p.exit_probability > 0;

-- -----------------------------------------------------------------------------
-- Step 2 · If everyone left on 31 March 2026
-- -----------------------------------------------------------------------------
SELECT
    COUNT(*)                                                                          AS employees_valued,
    COUNTIF(service_years >= vesting_years)                                           AS with_five_years,
    ROUND(SUM(annual_ctc) / 1e5, 1)                                                   AS annual_ctc_lakh,
    ROUND(SUM(accrued_old_wages) / 1e5, 2)                                            AS accrued_at_40_pct_wages_lakh,
    ROUND(SUM(accrued_new_wages) / 1e5, 2)                                            AS accrued_at_50_pct_wages_lakh,
    ROUND(100 * (SUM(accrued_new_wages) / SUM(accrued_old_wages) - 1), 1)             AS increase_pct,
    COUNTIF(accrued_new_wages >= ceiling)                                             AS at_the_ceiling
FROM `sahyadri_b2b.gr_accrued`;

SELECT employee_id, employee_name, designation, hire_date, ROUND(service_years, 1) AS service_years
FROM `sahyadri_b2b.gr_employees`
WHERE salary_missing;

-- -----------------------------------------------------------------------------
-- Step 3 · Projected unit credit: obligation and service cost, by wage basis
-- -----------------------------------------------------------------------------
WITH bases AS (
    SELECT '1. Current structure (wages 40 % of CTC)' AS basis, wage_share_old AS wage_share UNION ALL
    SELECT '2. Labour codes (wages 50 % of CTC)', wage_share_new
)
SELECT
    b.basis,
    ROUND(SUM(p.exit_probability * p.discount_factor
              * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * b.wage_share / 12
                                            * POW(1 + salary_growth, p.t - 1) * p.gratuity_years_at_exit), 0)
              * p.service_years / p.service_at_exit) / 1e5, 2)                        AS dbo_lakh,
    ROUND(SUM(p.exit_probability * p.discount_factor
              * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * b.wage_share / 12
                                            * POW(1 + salary_growth, p.t - 1) * p.gratuity_years_at_exit), 0)
              * 1 / p.service_at_exit) / 1e5, 2)                                      AS current_service_cost_lakh,
    -- expected gratuity paid in 2026-27: exits in year 1 that are vested
    ROUND(SUM(IF(p.t = 1, p.exit_probability
              * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * b.wage_share / 12 * p.gratuity_years_at_exit), 0), 0)) / 1e5, 2) AS expected_payout_2026_27_lakh
FROM `sahyadri_b2b.gr_projection` AS p
CROSS JOIN bases AS b
GROUP BY b.basis
ORDER BY b.basis;

-- Sensitivity of the obligation (labour-code wages) to each assumption, one at a time
WITH scenarios AS (
    SELECT '1. Base' AS scenario, discount_rate AS dr, salary_growth AS sg UNION ALL
    SELECT '2. Discount rate - 1 point', discount_rate - 0.01, salary_growth UNION ALL
    SELECT '3. Discount rate + 1 point', discount_rate + 0.01, salary_growth UNION ALL
    SELECT '4. Salary growth - 1 point', discount_rate, salary_growth - 0.01 UNION ALL
    SELECT '5. Salary growth + 1 point', discount_rate, salary_growth + 0.01
)
SELECT
    s.scenario,
    ROUND(SUM(p.exit_probability * POW(1 + s.dr, -(p.t - 0.5))
              * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * wage_share_new / 12
                                            * POW(1 + s.sg, p.t - 1) * p.gratuity_years_at_exit), 0)
              * p.service_years / p.service_at_exit) / 1e5, 2)                        AS dbo_lakh
FROM `sahyadri_b2b.gr_projection` AS p
CROSS JOIN scenarios AS s
GROUP BY s.scenario
ORDER BY s.scenario;

-- -----------------------------------------------------------------------------
-- Step 4 · Who carries the obligation
-- -----------------------------------------------------------------------------
WITH by_employee AS (
    SELECT p.employee_id,
           SUM(p.exit_probability * p.discount_factor
               * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * wage_share_new / 12
                                             * POW(1 + salary_growth, p.t - 1) * p.gratuity_years_at_exit), 0)
               * p.service_years / p.service_at_exit)                                 AS dbo
    FROM `sahyadri_b2b.gr_projection` AS p
    GROUP BY p.employee_id
)
SELECT
    a.department_name,
    COUNT(*)                                                                          AS employees,
    COUNTIF(a.service_years >= vesting_years)                                         AS with_five_years,
    ROUND(SUM(a.accrued_new_wages) / 1e5, 2)                                          AS accrued_if_all_left_lakh,
    ROUND(SUM(b.dbo) / 1e5, 2)                                                        AS dbo_lakh,
    ROUND(100 * SUM(b.dbo) / SUM(SUM(b.dbo)) OVER (), 1)                              AS share_pct
FROM `sahyadri_b2b.gr_accrued` AS a
JOIN by_employee AS b USING (employee_id)
GROUP BY a.department_name
ORDER BY dbo_lakh DESC;

WITH by_employee AS (
    SELECT p.employee_id,
           SUM(p.exit_probability * p.discount_factor
               * IF(p.vested_at_exit, LEAST(ceiling, 15 / 26 * p.annual_ctc * wage_share_new / 12
                                             * POW(1 + salary_growth, p.t - 1) * p.gratuity_years_at_exit), 0)
               * p.service_years / p.service_at_exit)                                 AS dbo
    FROM `sahyadri_b2b.gr_projection` AS p
    GROUP BY p.employee_id
)
SELECT
    CASE WHEN a.service_years < 3 THEN '1. Under 3 years'
         WHEN a.service_years < 5 THEN '2. 3 - 5 years (not yet eligible)'
         WHEN a.service_years < 8 THEN '3. 5 - 8 years'
         ELSE '4. 8 years and more' END                                                AS service_band,
    COUNT(*)                                                                          AS employees,
    ROUND(SUM(a.accrued_new_wages) / 1e5, 2)                                          AS accrued_if_all_left_lakh,
    ROUND(SUM(b.dbo) / 1e5, 2)                                                        AS dbo_lakh
FROM `sahyadri_b2b.gr_accrued` AS a
JOIN by_employee AS b USING (employee_id)
GROUP BY service_band
ORDER BY service_band;
