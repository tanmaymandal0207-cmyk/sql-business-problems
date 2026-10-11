/*BUSINESS PROBLEM:
Your company sells products to B2B customers. Management suspects that headline revenue is hiding three risks:
- Some customers look valuable because of one unusually large order.
- Some customers order frequently but contribute very little revenue.
- A small number of customers may account for a disproportionate share of company sales.
*/

WITH Order_Level_Revenue AS (
    SELECT
        O.Customer_id,
        O.order_id,
        SUM(
            S.quantity * S.unit_price
            * (1 - S.discount_percent / 100)
        ) AS Net_sales
    FROM `sahyadri_b2b.sales_order_items` AS S
    JOIN `sahyadri_b2b.Sales_Orders` AS O
        ON O.order_id = S.order_id
    GROUP BY
        O.order_id,
        O.customer_id
),

Customer_Revenue_Metrics AS (
    SELECT
        O.customer_id,
        COUNT(O.Order_id) AS Total_Orders,
        SUM(O.Net_sales) AS Customer_Net_Sales,
        MAX(O.Net_sales) AS Largest_Order,
        SUM(O.Net_sales) / COUNT(O.Order_id) AS Customer_AOV,
        MAX(O.Net_sales) / SUM(O.Net_sales) * 100
            AS Largest_Order_Contribution_Pct
    FROM Order_Level_Revenue AS O
    GROUP BY
        O.customer_id
),

Company_Revenue AS (
    SELECT
        SUM(
            S.quantity * S.unit_price
            * (1 - S.discount_percent / 100)
        ) AS Company_Sales
    FROM `sahyadri_b2b.sales_order_items` AS S
),

Customer_Revenue_Analysis AS (
    SELECT
        C.Customer_id,
        C.Total_Orders,
        C.Customer_Net_Sales AS Net_Sales,
        C.Customer_AOV,
        C.Largest_Order,
        C.Largest_Order_Contribution_Pct,
        R.Company_Sales
    FROM Customer_Revenue_Metrics AS C
    CROSS JOIN Company_Revenue AS R
)

SELECT
    O.Customer_id,
    O.Total_Orders,
    O.Net_Sales,
    O.Customer_AOV,
    O.Largest_Order,

    O.Largest_Order / O.Net_Sales * 100
        AS Largest_Order_Contribution_Pct,

    O.Net_Sales / O.Company_Sales * 100
        AS Company_Sales_Contribution_Pct,

    DENSE_RANK() OVER (
        ORDER BY O.Net_Sales DESC
    ) AS Customer_Sales_Rank,

    DENSE_RANK() OVER (
        ORDER BY
            O.Largest_Order / O.Net_Sales * 100 DESC
    ) AS Concentration_Rank,

    CASE
        WHEN O.Largest_Order / O.Net_Sales * 100 >= 50
            THEN 'Critical Concentration'
        WHEN O.Largest_Order / O.Net_Sales * 100
            BETWEEN 30 AND 50
            THEN 'Moderate Concentration'
        WHEN O.Largest_Order / O.Net_Sales * 100 < 30
            THEN 'Diversified'
        ELSE 'Unclassified'
    END AS Risk_Flag,

    CASE
        WHEN O.Net_Sales >= 1000000
             AND O.Total_Orders >= 20
            THEN 'Strategic'
        WHEN O.Net_Sales >= 1000000
             AND O.Total_Orders < 20
            THEN 'High Value'
        WHEN O.Net_Sales < 1000000
             AND O.Total_Orders >= 20
            THEN 'High Frequency'
        WHEN O.Net_Sales < 1000000
             AND O.Total_Orders < 20
            THEN 'Standard'
        ELSE 'Uncategorised'
    END AS Customer_Segment

FROM Customer_Revenue_Analysis AS O
WHERE O.Total_Orders >= 5
ORDER BY
    Customer_Sales_Rank ASC,
    Concentration_Rank ASC
    ;

/*
VALIDATION:
For a reconciliation check, remove the final WHERE filter
and save the unfiltered customer-level result as
Customer_Revenue_Check before running the query below.

Compare customer-level revenue against company-level revenue.


SELECT
SUM(C.Net_Sales) AS Customer_Sales,
R.Company_Sales
FROM Customer_Revenue_Check AS C
CROSS JOIN Company_Revenue AS R
GROUP BY
R.Company_Sales;
*/
