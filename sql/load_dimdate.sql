WITH digits AS (
    SELECT n
    FROM (VALUES (0),(1),(2),(3),(4),
                 (5),(6),(7),(8),(9)) AS d(n)
),
numbers AS (
    SELECT
        ones.n + tens.n * 10 + hundreds.n * 100 AS n
    FROM digits ones
    CROSS JOIN digits tens
    CROSS JOIN digits hundreds
),
dates AS (
    SELECT
        DATEADD(DAY, n, CAST('2026-09-01' AS DATE)) AS full_date
    FROM numbers
    WHERE n <= DATEDIFF(
        DAY,
        CAST('2026-09-01' AS DATE),
        CAST('2026-12-31' AS DATE)
    )
)
INSERT INTO gold.dim_date (
    date_key, full_date, year_number,
    quarter_number, quarter_name,
    month_number, month_name, month_short,
    year_month, year_month_sort,
    week_number, week_start,
    day_of_month, day_of_year, day_of_week,
    day_name, day_type, is_weekend
)
SELECT
    YEAR(full_date) * 10000
        + MONTH(full_date) * 100
        + DAY(full_date),

    full_date,
    YEAR(full_date),
    DATEPART(QUARTER, full_date),
    CONCAT('Q', DATEPART(QUARTER, full_date)),
    MONTH(full_date),
    DATENAME(MONTH, full_date),
    LEFT(DATENAME(MONTH, full_date), 3),
    CONVERT(VARCHAR(7), full_date, 120),
    YEAR(full_date) * 100 + MONTH(full_date),
    DATEPART(ISO_WEEK, full_date),

    DATEADD(
        DAY,
        -(DATEDIFF(DAY, '19000101', full_date) % 7),
        full_date
    ),

    DAY(full_date),
    DATEPART(DAYOFYEAR, full_date),
    (DATEDIFF(DAY, '19000101', full_date) % 7) + 1,
    DATENAME(WEEKDAY, full_date),

    CASE
        WHEN DATEDIFF(DAY, '19000101', full_date) % 7 >= 5
        THEN 'Weekend'
        ELSE 'Weekday'
    END,

    CASE
        WHEN DATEDIFF(DAY, '19000101', full_date) % 7 >= 5
        THEN 1
        ELSE 0
    END
FROM dates;