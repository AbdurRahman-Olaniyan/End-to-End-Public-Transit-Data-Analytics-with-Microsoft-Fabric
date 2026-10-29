# Data Pipeline Orchestration

## Overview

The `pl_mbta_predictions_etl` pipeline coordinates prediction ingestion, Silver and Gold processing, and semantic model refresh in Microsoft Fabric Data Factory. Its activities run in sequence so that each stage follows the preceding stage. The pipeline is shown below as configured in the project.

![Prediction data pipeline](data_pipeline.png)

## Pipeline Activities

The `ingest_predictions` activity runs the `predictions_ingest_bronze` notebook, which requests MBTA Red Line predictions and appends the records to the Bronze Lakehouse table. The `merge_predictions` activity then runs `silver.usp_merge_predictions` to process records newer than the saved watermark, enrich the selected predictions, and merge them into the Silver table.

Next, `build_gold` runs `gold.usp_build_gold` to update the Gold route, stop, and trip dimensions and the predictions fact table. The last activity, `Semantic model refresh`, refreshes the semantic model used for reporting.

## Recreating the Pipeline

1. Create a Data Pipeline in the Fabric workspace and name it `pl_mbta_predictions_etl`.
2. Add a Notebook activity named `ingest_predictions` and select the `predictions_ingest_bronze` notebook.
3. Add a stored procedure activity named `merge_predictions` and configure it to run `silver.usp_merge_predictions` in the Fabric Warehouse.
4. Add another stored procedure activity named `build_gold` and configure it to run `gold.usp_build_gold`.
5. Add the semantic model refresh activity for the report model. Connect the activities in the order shown in the pipeline screenshot, then run the pipeline and inspect its activity results.

The referenced Lakehouse, Warehouse tables, notebooks, stored procedures, and semantic model must already be available and the pipeline activity settings and connections must be configured in the Fabric workspace.

## Execution and Monitoring

The Bronze prediction notebook and the Silver and Gold procedures write execution details to `control.pipeline_runs`. The Silver procedure also updates `control.watermark` after processing. Fabric pipeline run history provides the status of each pipeline execution and its activities.

![Recent pipeline runs](recent_data_pipeline_run_history.png)

To retrieve predictions regularly, configure a pipeline schedule at the required interval, such as every 15 minutes. The powerbi report's data freshness depends on the semantic model refresh.
