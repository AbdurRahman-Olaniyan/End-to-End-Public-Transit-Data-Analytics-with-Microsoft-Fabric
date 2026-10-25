# Silver Predictions Merge

## Overview

The `silver.usp_merge_predictions` stored procedure loads MBTA Red Line prediction records from the Bronze Lakehouse table `LH_MBTA.bronze.predictions_raw` into `silver.predictions`. It uses the `ingested_at` timestamp to process records added since the previous run. The procedure also reads route, stop, and trip reference tables from the Bronze layer.

## Incremental Processing

The procedure reads the saved watermark for `predictions_red_line` from `control.watermark`. If the watermark is missing, it raises an error and stops processing. It counts Bronze records ingested after the watermark and finds the latest ingestion timestamp to use as the next watermark.

Within the new records, `ROW_NUMBER()` identifies the most recently ingested row for each non-null `prediction_id`. Only that row is selected for the merge. The procedure joins each prediction to the available route, stop, and trip records using left joins, so a missing reference record does not exclude the prediction.

## Silver Transformations and Merge

The source query adds the route name, stop name, and trip headsign. It converts scheduled and predicted departure times to `DATETIME2(6)` and calculates `delay_minutes` as the difference in minutes between them. It sets `is_revenue_trip` to zero when `schedule_relationship` is `ADDED` and `schedule_id` is null, and to one otherwise.

The `MERGE` matches records by `prediction_id`. Existing Silver records are updated when the incoming `ingested_at` value is equal to or later than the stored value. Predictions without a matching Silver record are inserted. The procedure records the number of rows affected by the merge.

## Watermark and Run Logging

After the merge, the procedure updates `control.watermark` with the new ingestion timestamp, the run time, and the number of affected rows. If no newer timestamp is found, it keeps the existing watermark.

Each execution is recorded in `control.pipeline_runs` under the `silver_merge` stage. Successful runs are logged with a `SUCCESS` status. If an error occurs, the procedure attempts to log a `FAILED` status with the error message and then raises the error again.