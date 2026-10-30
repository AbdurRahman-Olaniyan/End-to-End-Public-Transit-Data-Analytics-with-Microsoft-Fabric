SELECT
    s.stop_name,
    COUNT(f.delay_minutes) AS total_predictions,
    SUM(CASE
        WHEN f.delay_minutes > 5 THEN 1
        ELSE 0
    END) AS late_predictions,
    CAST(
        100.0 * SUM(CASE
            WHEN f.delay_minutes > 5 THEN 1
            ELSE 0
        END)
        / NULLIF(COUNT(f.delay_minutes), 0)
        AS DECIMAL(5,2)
    ) AS late_prediction_pct,
    CAST(
        AVG(CAST(f.delay_minutes AS FLOAT))
        AS DECIMAL(10,2)
    ) AS avg_predicted_delay_min
FROM gold.fact_predictions AS f
INNER JOIN gold.dim_stop AS s
    ON f.stop_key = s.stop_key
WHERE f.delay_minutes IS NOT NULL
GROUP BY s.stop_id, s.stop_name
HAVING COUNT(f.delay_minutes) >= 20
ORDER BY late_prediction_pct DESC, total_predictions DESC;