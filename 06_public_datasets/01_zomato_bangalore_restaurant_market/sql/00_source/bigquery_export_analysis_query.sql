SELECT                                  -- Clean Table Check
    COUNT(*) AS total_records,
    COUNT(DISTINCT url) AS unique_urls,
    COUNTIF(approx_cost_cleaned IS NULL) AS null_costs,
    COUNTIF(votes_cleaned IS NULL) AS null_votes
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`;

SELECT                                          ----- Data Type Check
    column_name,
    data_type
FROM `zomatoanalytics.Zomato_csv.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'restaurants_clean'
ORDER BY ordinal_position;

SELECT                                          ----- Schema Validation
    column_name,
    data_type
FROM `zomatoanalytics.Zomato_csv.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'restaurants_clean'
AND column_name IN (
    'approx_cost_cleaned',
    'rate_cleaned',
    'votes_cleaned',
    'address_cleaned',
    'phone_cleaned',
    'menu_item_cleaned'
)
ORDER BY ordinal_position;
---------------------------------------------------------------------------------------------
/* 
Business scenario

Imagine you're advising a food-delivery company that wants to understand restaurant concentration across Bangalore.

The company wants to identify which localities have the largest restaurant presence.

Your task:

Using restaurants_clean, write a query that returns:
Column	                Requirement
location	            Locality name
restaurant_count	    Number of restaurant records
average_rating	        Average restaurant rating

Additional requirements:
1. Exclude records where location is NULL.
2. Calculate average rating using rate_cleaned.
3. Remember that ratings contain values such as 4.1/5, NEW and possibly -.
4. Sort by restaurant count, highest first.
5. Return the top 15 localities.
*/

SELECT
location,
Count(*) as Restaurant_Count,
Round(Avg(SAFE_CAST(
    SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating
from
`zomatoanalytics.Zomato_csv.restaurants_clean`
where location is not null
Group by
Location
ORDER BY restaurant_count DESC

LIMIT 15;
---------------------------------------------------------------------------------------------------------------------------
/*
Challenge 01 — Restaurant distribution
Difficulty 1/5
 Aggregation


Scenario: A food-delivery company wants to identify the most attractive localities for expansion.

Your task: Produce a locality-level report with four metrics:
Column	                What it represents
location	            Locality
restaurant_count	    Total restaurants
rated_restaurant_count	Restaurants with valid numerical ratings
average_rating	        Average numerical rating, rounded to 1 decimal

Requirements:
- Exclude NULL locations.
- Ignore NEW and - ratings.
- Sort by restaurant count descending.
- Return the top 15 localities.
SQL concepts to use:
- COUNT(*)
- COUNTIF()
- SAFE_CAST()
- SPLIT()
- AVG()
- ROUND() */

SELECT
location,
countif(name is not null) as Outlets,
countif(rate_cleaned is not null) as Rated_Resturant_Count,
Round(Avg(SAFE_CAST(
    SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating
from
`zomatoanalytics.Zomato_csv.restaurants_clean`
where location is not null
Group by 
Location
having Avg_Rating is not null
Order by
Rated_Resturant_Count Desc, Avg_Rating DESC 
Limit 15
;

-----------------------------------------------------------------------------------------------------------------------
/* 3. Now solve Question 2
Business scenario: An investor wants to identify highly rated localities, but doesn't want to consider localities with very few restaurants.

Requirements:
- At least 500 restaurants per locality.
- Only valid numerical ratings in average calculation.
- Top 10 localities by average rating.
- Show location, restaurant count and average rating.
Difficulty 2/5
One hint: You will need both WHERE and HAVING.

Your turn: Write the query.

I particularly want to see whether you can distinguish the number of restaurants from the number of restaurants with valid ratings without my giving you the solution. */

SELECT
    Location,
    Countif(name is not null) as Outlets,
    Round(Avg(SAFE_CAST(
        SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating

from
`zomatoanalytics.Zomato_csv.restaurants_clean`
where location is not null
Group by location
Having Outlets >= 500 and
Avg_Rating is not null
Order by  Avg_Rating Desc, Outlets DESC
Limit 15
;

---------------------------------------------------------------------------------------------------------------
/*
Let's make the analysis more business-oriented.
Business question:
Identify the top 10 locations with the highest percentage of restaurants accepting online orders.

Requirements:
- Location
- Total outlets
- Restaurants accepting online orders
- Online order acceptance percentage
- Only locations with at least 300 outlets
- Highest acceptance percentage first */

SELECT
    Location,
    Countif(name is not null) as Outlets,
    Round(Avg(SAFE_CAST(
        SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating,
    Sum(Case when online_order = 'Yes' then 1
             ELse 0 end) as Online_Acceptance_Count,
    Round(Safe_Divide(Sum(Case when online_order = 'Yes' then 1
             ELse 0 end), Countif(name is not null)*100)) as Online_Acceptance_Percentage  
from
`zomatoanalytics.Zomato_csv.restaurants_clean`
Where location is not null
Group by location
Having Outlets >= 300
Order by
Online_Acceptance_Percentage Desc
Limit 10;
----------------------------------------------------------------------------------------------------
/*
Management wants to identify locations where restaurants have strong ratings but relatively low online-order adoption.

Find the top 10 locations satisfying:
1. At least 300 outlets.
2. Average restaurant rating of at least 3.8.
3. Calculate the percentage of restaurants that do NOT accept online orders.
4. Show total outlets, average rating and offline-order percentage.
5. Rank by offline-order percentage, highest first.
Concepts you'll practise:
- COUNTIF()
- AVG()
- SAFE_CAST()
- HAVING
- ORDER BY
- Percentage calculations */

SELECT
    Location,
    Countif(Name is not null) as Total_Outlets ,
    Round(Avg(SAFE_CAST(
            SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating,
    ROUND(
    SAFE_DIVIDE(
        COUNTIF(online_order = 'No'),
        COUNT(*)
    ) * 100,
    2
) AS Offline_Outlet_Percentage
from
`zomatoanalytics.Zomato_csv.restaurants_clean`
where location is not null
Group by Location
Having Avg_Rating >= 3.8
and total_Outlets >= 300
Order by
Offline_Outlet_Percentage DESC 
Limit 10
;

---------------------------------------------------------------------------------------------------------------------
/*
Business scenario: Management wants to understand which cuisines have the strongest restaurant presence in Bangalore.

Find the top 15 individual cuisines by restaurant count.

Requirements:
1. Extract individual cuisines from the cuisines column.
2. Remove unnecessary whitespace around cuisine names.
3. Count restaurants offering each cuisine.
4. Exclude NULL and empty cuisine values.
5. Rank by restaurant count, descending. */

SELECT
location,
Trim(cuisines) as Cuisines,
Count(distinct url) as Outlets_Count
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
, UNNEST (Split(Cuisines,',')) as Cuisines   

GROUP BY
location,Cuisines 
ORDER BY Outlets_Count Desc    
Limit 15;
------------------------------------------------------------------------------------------------------------
/*
Business question:

Which cuisines have the highest average restaurant rating across Bangalore?

Requirements:
1. Expand the cuisines column using UNNEST.
2. Calculate the number of restaurants serving each individual cuisine.
3. Calculate the average rating for each cuisine.
4. Only include cuisines served by at least 100 restaurants.
5. Round average ratings to 2 decimal places.
6. Display the top 15 cuisines by average rating.
Use:
- restaurants_clean
- rate_cleaned
- url */

SELECT
    
    name as Resturants,
    Round(Avg(SAFE_CAST(
            SPLIT(rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),2) as Avg_Rating,
    Count(distinct url) as Outlets_Count,
    Trim(cuisines) as Cuisines
    
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
, UNNEST (Split(Cuisines,',')) as Cuisines   

GROUP BY
Resturants,Cuisines 
HAVING Outlets_Count >= 70
ORDER BY Avg_Rating Desc,Outlets_Count Desc
Limit 15;

-------------------------------------------------------------------------------------------------------
/*
Business question:

Which cuisines have the highest average restaurant rating across Bangalore?

Requirements:
1. Expand the cuisines column using UNNEST.
2. Calculate the number of restaurants serving each individual cuisine.
3. Calculate the average rating for each cuisine.
4. Only include cuisines served by at least 100 restaurants.
5. Round average ratings to 2 decimal places.
6. Display the top 15 cuisines by average rating.*/

WITH CTE_Location as
(
SELECT

    location,
    Count(Distinct url) as Outlets,

FROM `zomatoanalytics.Zomato_csv.restaurants_clean`
Group by location
Having Outlets >= 100
)
SELECT
    L.Location,
    Trim(Cuisines) as Cuisines,
    Count(Distinct Z.url) as Outlets,
    Round(Avg(SAFE_CAST(
                SPLIT(Z.rate_cleaned,'/')[SAFE_OFFSET(0)] as Float64)),1) as Avg_Rating,
    Countif(Z.online_order = 'Yes')/Count(Distinct Z.Url)*100 as Online_Accepted_Outlet_Percentage

FROM `zomatoanalytics.Zomato_csv.restaurants_clean` as Z
CROSS JOIN Unnest(Split(Z.Cuisines,',')) as cuisines
JOIN CTE_Location as L
on Z.location = L.Location
Group by L.Location, Cuisines
Having Outlets >= 30
ORDER BY Avg_Rating DESC
;
------------------------------------------------------------------------------------------------------
/*
Business scenario:

Zomato's market research team wants to identify locations where restaurants offer a diverse range of cuisines and have strong online ordering adoption.

Build a query showing:
1. location
2. Total unique restaurants in that location
3. Number of distinct cuisines available
4. Most popular cuisine (highest outlet count)
5. Online ordering acceptance percentage
Conditions:
- Only locations with at least 300 restaurants.
- Only consider cuisines offered by at least 20 outlets in a location.
- Sort by online ordering acceptance percentage, descending.*/

With CTE_Location as
(
SELECT
location,
Count(Distinct url) as Outlets,
Count(Distinct Menu) as Cuisines,
Count(Distinct if(online_order = 'Yes',url,null)) as Online_Availablity
FROM `zomatoanalytics.Zomato_csv.restaurants_clean`,
UNNEST (SPLIT(cuisines,',')) as Menu
Group by
location
having Outlets >= 100
)
SELECT
    Location,
    Outlets,
    Cuisines AS Distinct_Cuisines,
    ROUND(
        SAFE_DIVIDE(Online_Availablity, Outlets) * 100,
        2
    ) AS Online_Ordering_Acceptance
FROM CTE_Location
ORDER BY Outlets DESC;
















