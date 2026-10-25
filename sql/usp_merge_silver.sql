CREATE OR ALTER PROCEDURE silver.usp_merge_predictions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @source_name    VARCHAR(100) = 'predictions_red_line';
    DECLARE @watermark      DATETIME2(6);
    DECLARE @new_rows_count INT;
    DECLARE @new_watermark  DATETIME2(6);
    DECLARE @run_id         VARCHAR(36)  = CAST(NEWID() AS VARCHAR(36));
    DECLARE @started_at     DATETIME2(6) = SYSUTCDATETIME();
    DECLARE @rows_affected  INT = 0;
    DECLARE @error_message  VARCHAR(4000) = NULL;

    BEGIN TRY

        SELECT @watermark = watermark_value
        FROM control.watermark
        WHERE source_name = @source_name;

        PRINT CONCAT('watermark read: ', ISNULL(CONVERT(VARCHAR, @watermark, 121), 'NULL'));

        IF @watermark IS NULL
        BEGIN
            RAISERROR('No watermark found for source_name = predictions_red_line. Aborting.', 16, 1);
        END

        SELECT @new_rows_count = COUNT(*)
        FROM LH_MBTA.bronze.predictions_raw
        WHERE ingested_at > @watermark;

        PRINT CONCAT('new bronze rows found: ', @new_rows_count);

        SELECT @new_watermark = MAX(ingested_at)
        FROM LH_MBTA.bronze.predictions_raw
        WHERE ingested_at > @watermark;

        PRINT CONCAT('new watermark: ', ISNULL(CONVERT(VARCHAR, @new_watermark, 121), 'NULL'));

        MERGE silver.predictions AS target
        USING (
            SELECT
                b.prediction_id,
                b.route_id,
                r.long_name AS route_long_name,
                b.trip_id,
                t.headsign AS trip_headsign,
                b.stop_id,
                s.name AS stop_name,
                b.direction_id,
                CASE 
                    WHEN b.schedule_relationship = 'ADDED' 
                        AND b.schedule_id IS NULL 
                    THEN 0 
                    ELSE 1
                END AS is_revenue_trip,
                CAST(b.predicted_departure_time AS DATETIME2(6)) AS predicted_departure_time,
                CAST(b.scheduled_departure_time AS DATETIME2(6)) AS scheduled_departure_time,
                DATEDIFF(
                    MINUTE, 
                    CAST(b.scheduled_departure_time AS DATETIME2(6)), 
                    CAST(b.predicted_departure_time AS DATETIME2(6))) AS delay_minutes,
                b.ingested_at
            FROM (
                -- latest prediction per prediction_id
                SELECT *,
                    ROW_NUMBER() OVER (PARTITION BY prediction_id ORDER BY ingested_at DESC) AS rn
                FROM LH_MBTA.bronze.predictions_raw
                WHERE ingested_at > @watermark
                    AND prediction_id IS NOT NULL 
            ) b
            LEFT JOIN (
                -- Latest route per route_id
                SELECT
                    route_id,
                    long_name,
                    ROW_NUMBER() OVER (PARTITION BY route_id ORDER BY ingested_at DESC) AS rn
                FROM LH_MBTA.bronze.routes_raw
            ) r
                ON b.route_id = r.route_id AND r.rn = 1
            LEFT JOIN (
                -- Latest stop per stop_id
                SELECT
                    stop_id,
                    name,
                    ROW_NUMBER() OVER (PARTITION BY stop_id ORDER BY ingested_at DESC ) as rn
                FROM LH_MBTA.bronze.stops_raw
            ) s
                ON b.stop_id = s.stop_id AND s.rn = 1
            LEFT JOIN (
                -- Latest trip per trip_id
                SELECT
                    trip_id,
                    headsign,
                    ROW_NUMBER() OVER (PARTITION BY trip_id ORDER BY ingested_at DESC) AS rn
                FROM LH_MBTA.bronze.trips_raw
            ) t
                ON b.trip_id = t.trip_id AND t.rn = 1
            
            WHERE b.rn = 1
        ) AS source
        ON target.prediction_id = source.prediction_id
        WHEN MATCHED  AND source.ingested_at >= target.ingested_at THEN
            UPDATE SET
                route_id = source.route_id, route_long_name = source.route_long_name,
                trip_id = source.trip_id, trip_headsign = source.trip_headsign,
                stop_id = source.stop_id, stop_name = source.stop_name,
                direction_id = source.direction_id, is_revenue_trip = source.is_revenue_trip,
                predicted_departure_time = source.predicted_departure_time,
                scheduled_departure_time = source.scheduled_departure_time,
                delay_minutes = source.delay_minutes, ingested_at = source.ingested_at
        WHEN NOT MATCHED THEN
            INSERT (prediction_id, route_id, route_long_name, trip_id, trip_headsign, stop_id, stop_name,
                    direction_id, is_revenue_trip, predicted_departure_time, scheduled_departure_time,
                    delay_minutes, ingested_at)
            VALUES (source.prediction_id, source.route_id, source.route_long_name, source.trip_id, source.trip_headsign,
                    source.stop_id, source.stop_name, source.direction_id, source.is_revenue_trip,
                    source.predicted_departure_time, source.scheduled_departure_time, source.delay_minutes, source.ingested_at);

        SET @rows_affected = @@ROWCOUNT;
        PRINT CONCAT('STEP 4 - merge rows affected: ', @rows_affected);

        UPDATE control.watermark
        SET watermark_value = COALESCE(@new_watermark, watermark_value),
            last_run_at = SYSUTCDATETIME(),
            rows_processed_last_run = @rows_affected
        WHERE source_name = @source_name;

        INSERT INTO control.pipeline_runs (run_id, pipeline_run_id, stage_name, status, rows_affected, started_at, completed_at, error_message)
        VALUES (@run_id, NULL, 'silver_merge', 'SUCCESS', @rows_affected, @started_at, SYSUTCDATETIME(), NULL);

    END TRY
    BEGIN CATCH
        SET @error_message = ERROR_MESSAGE();
        INSERT INTO control.pipeline_runs (run_id, pipeline_run_id, stage_name, status, rows_affected, started_at, completed_at, error_message)
        VALUES (@run_id, NULL, 'silver_merge', 'FAILED', @rows_affected, @started_at, SYSUTCDATETIME(), @error_message);
        THROW;
    END CATCH
END;
GO