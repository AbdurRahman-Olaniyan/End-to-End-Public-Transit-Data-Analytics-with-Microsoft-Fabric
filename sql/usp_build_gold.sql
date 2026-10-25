CREATE OR ALTER PROCEDURE gold.usp_build_gold
AS
BEGIN
    DECLARE @run_id        VARCHAR(36)  = CAST(NEWID() AS VARCHAR(36));
    DECLARE @started_at    DATETIME2(6) = SYSUTCDATETIME();
    DECLARE @rows_affected INT = 0;
    DECLARE @error_message VARCHAR(4000) = NULL;

    BEGIN TRY

        -- DIM ROUTE
        MERGE gold.dim_route AS target
        USING (
            SELECT route_id, MAX(route_long_name) AS route_long_name
            FROM silver.predictions
            WHERE route_id IS NOT NULL
            GROUP BY route_id
        ) AS source
        ON target.route_id = source.route_id
        WHEN MATCHED THEN
            UPDATE SET route_long_name = source.route_long_name
        WHEN NOT MATCHED THEN
            INSERT (route_id, route_long_name)
            VALUES (source.route_id, source.route_long_name);


        -- DIM STOP
        MERGE gold.dim_stop AS target
        USING (
            SELECT stop_id, MAX(stop_name) AS stop_name
            FROM silver.predictions
            WHERE is_revenue_trip = 1
              AND stop_id IS NOT NULL
            GROUP BY stop_id
        ) AS source
        ON target.stop_id = source.stop_id
        WHEN MATCHED THEN
            UPDATE SET stop_name = source.stop_name
        WHEN NOT MATCHED THEN
            INSERT (stop_id, stop_name)
            VALUES (source.stop_id, source.stop_name);


        -- DIM TRIP
        MERGE gold.dim_trip AS target
        USING (
            SELECT
                trip_id,
                MAX(trip_headsign) AS trip_headsign,
                MAX(direction_id) AS direction_id
            FROM silver.predictions
            WHERE is_revenue_trip = 1
              AND trip_id IS NOT NULL
            GROUP BY trip_id
        ) AS source
        ON target.trip_id = source.trip_id
        WHEN MATCHED THEN
            UPDATE SET
                trip_headsign = source.trip_headsign,
                direction_id = source.direction_id
        WHEN NOT MATCHED THEN
            INSERT (trip_id, trip_headsign, direction_id)
            VALUES (
                source.trip_id,
                source.trip_headsign,
                source.direction_id
            );


        -- ASSIGN SURROGATE KEYS TO NEW DIMENSION ROWS

        DECLARE @max_route_key BIGINT =
            (SELECT COALESCE(MAX(route_key), 0) FROM gold.dim_route);

        DECLARE @max_stop_key BIGINT =
            (SELECT COALESCE(MAX(stop_key), 0) FROM gold.dim_stop);

        DECLARE @max_trip_key BIGINT =
            (SELECT COALESCE(MAX(trip_key), 0) FROM gold.dim_trip);


        UPDATE gold.dim_route
        SET route_key = x.new_key
        FROM (
            SELECT
                route_id,
                @max_route_key +
                ROW_NUMBER() OVER (ORDER BY route_id) AS new_key
            FROM gold.dim_route
            WHERE route_key IS NULL
        ) x
        WHERE gold.dim_route.route_id = x.route_id;


        UPDATE gold.dim_stop
        SET stop_key = x.new_key
        FROM (
            SELECT
                stop_id,
                @max_stop_key +
                ROW_NUMBER() OVER (ORDER BY stop_id) AS new_key
            FROM gold.dim_stop
            WHERE stop_key IS NULL
        ) x
        WHERE gold.dim_stop.stop_id = x.stop_id;


        UPDATE gold.dim_trip
        SET trip_key = x.new_key
        FROM (
            SELECT
                trip_id,
                @max_trip_key +
                ROW_NUMBER() OVER (ORDER BY trip_id) AS new_key
            FROM gold.dim_trip
            WHERE trip_key IS NULL
        ) x
        WHERE gold.dim_trip.trip_id = x.trip_id;


        -- FACT PREDICTIONS
        MERGE gold.fact_predictions AS target
        USING (
            SELECT
                p.prediction_id,
                r.route_key,
                s.stop_key,
                t.trip_key,
                CASE
                    WHEN p.scheduled_departure_time IS NOT NULL
                    THEN YEAR(p.scheduled_departure_time) * 10000
                        + MONTH(p.scheduled_departure_time) * 100
                        + DAY(p.scheduled_departure_time)
                END AS date_key,
                DATEPART(HOUR, p.scheduled_departure_time)
                    AS departure_hour,
                CASE
                    WHEN p.delay_minutes IS NULL THEN NULL
                    WHEN p.delay_minutes < 0 THEN 'Early'
                    WHEN p.delay_minutes <= 2 THEN '0-2 min'
                    WHEN p.delay_minutes <= 5 THEN '3-5 min'
                    WHEN p.delay_minutes <= 10 THEN '6-10 min'
                    ELSE 'Over 10 min'
                END AS delay_band,
                CASE
                    WHEN p.delay_minutes IS NULL THEN NULL
                    WHEN p.delay_minutes < 0 THEN 1
                    WHEN p.delay_minutes <= 2 THEN 2
                    WHEN p.delay_minutes <= 5 THEN 3
                    WHEN p.delay_minutes <= 10 THEN 4
                    ELSE 5
                END AS delay_band_sort,
                p.predicted_departure_time,
                p.scheduled_departure_time,
                p.delay_minutes,
                p.ingested_at

            FROM silver.predictions p

            LEFT JOIN gold.dim_route r
                ON p.route_id = r.route_id

            LEFT JOIN gold.dim_stop s
                ON p.stop_id = s.stop_id

            LEFT JOIN gold.dim_trip t
                ON p.trip_id = t.trip_id

            WHERE p.is_revenue_trip = 1

        ) AS source

        ON target.prediction_id = source.prediction_id

        WHEN MATCHED THEN
            UPDATE SET
                route_key = source.route_key,
                stop_key = source.stop_key,
                trip_key = source.trip_key,
                date_key = source.date_key,
                target.departure_hour = source.departure_hour,
                target.delay_band = source.delay_band,
                target.delay_band_sort = source.delay_band_sort,
                predicted_departure_time =
                    source.predicted_departure_time,
                scheduled_departure_time =
                    source.scheduled_departure_time,
                delay_minutes = source.delay_minutes,
                ingested_at = source.ingested_at

        WHEN NOT MATCHED THEN
            INSERT (
                prediction_id,
                route_key,
                stop_key,
                trip_key,
                date_key,
                departure_hour,
                delay_band,
                delay_band_sort,
                predicted_departure_time,
                scheduled_departure_time,
                delay_minutes,
                ingested_at
            )
            VALUES (
                source.prediction_id,
                source.route_key,
                source.stop_key,
                source.trip_key,
                source.date_key,
                source.departure_hour,
                source.delay_band,
                source.delay_band_sort,
                source.predicted_departure_time,
                source.scheduled_departure_time,
                source.delay_minutes,
                source.ingested_at
            );


        SET @rows_affected = @@ROWCOUNT;

        INSERT INTO control.pipeline_runs (
            run_id,
            pipeline_run_id,
            stage_name,
            status,
            rows_affected,
            started_at,
            completed_at,
            error_message
        )
        VALUES (
            @run_id,
            NULL,
            'gold_build',
            'SUCCESS',
            @rows_affected,
            @started_at,
            SYSUTCDATETIME(),
            NULL
        );

    END TRY

    BEGIN CATCH

        SET @error_message = ERROR_MESSAGE();

        INSERT INTO control.pipeline_runs (
            run_id,
            pipeline_run_id,
            stage_name,
            status,
            rows_affected,
            started_at,
            completed_at,
            error_message
        )
        VALUES (
            @run_id,
            NULL,
            'gold_build',
            'FAILED',
            @rows_affected,
            @started_at,
            SYSUTCDATETIME(),
            @error_message
        );

        THROW;

    END CATCH
END;
GO