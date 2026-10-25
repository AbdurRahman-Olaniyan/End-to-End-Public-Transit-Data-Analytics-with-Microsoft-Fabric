# Gold Layer — Build Procedure

## Overview

The `gold.usp_build_gold` stored procedure loads data from `silver.predictions` into the Gold tables. It updates the route, stop, and trip dimensions, assigns keys to new dimension records, and then loads the predictions fact table. The procedure uses SQL `MERGE` statements to insert records that are not present and update records that already exist.

## Dimension Tables

The procedure builds `gold.dim_route` from distinct route IDs in Silver and uses `MAX(route_long_name)` to select a route name for each ID. It builds `gold.dim_stop` and `gold.dim_trip` from records where `is_revenue_trip = 1`, excluding null stop and trip IDs. For each stop and trip, it groups records by ID and uses `MAX` to select the stored descriptive values. Existing dimension records are updated, while new IDs are inserted.

After the dimension merges, the procedure assigns surrogate keys to records whose route, stop, or trip key is null. It starts from the current maximum key in each dimension and uses `ROW_NUMBER()` to number the new records. Existing non-null keys are left unchanged.

## Predictions Fact Table

The procedure loads `gold.fact_predictions` from Silver records where `is_revenue_trip = 1`. It joins those records to the Gold dimensions to retrieve route, stop, and trip keys. It also derives a numeric date key from the scheduled departure date, extracts the scheduled departure hour, and groups the delay in minutes into the `Early`, `0-2 min`, `3-5 min`, `6-10 min`, or `Over 10 min` bands. A separate numeric field sets the order of these bands.

The fact table is merged using `prediction_id`. A matching prediction is updated with the current source values; a new prediction is inserted. The procedure does not contain a delete operation for records already in the fact table.

## Execution Logging

After the fact merge, the procedure records the number of affected fact rows using `@@ROWCOUNT` and writes a `SUCCESS` entry to `control.pipeline_runs`. If an error is caught, it records a `FAILED` entry with the error message and raises the error again. Each run has a generated run ID and UTC start and completion timestamps. The SQL does not update a watermark in this procedure.