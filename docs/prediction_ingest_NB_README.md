# MBTA Red Line Prediction Ingestion

## Overview

The `predictions_ingest_bronze` notebook ingests MBTA Red Line prediction data from the MBTA V3 API into Microsoft Fabric Lakehouse. It is the Bronze ingestion step for prediction records in the data pipeline. The notebook uses Python to request the API response, prepare the records, and create a PySpark DataFrame with an explicit schema before writing the data to Lkehouse table.

The notebook retains predictions attributes and related schedule information. Each record also receives an ingestion timestamp. The notebook records the outcome of each execution in a separate Fabric Data Warehouse table, providing a basic operational history of successful and failed ingestion runs.

## Source and Configuration

The source is the MBTA V3 `predictions` endpoint (`https://api-v3.mbta.com/predictions`). The request applies `filter[route]=Red` to retrieve predictions for the Red Line and uses 'include=schedule' to request associated schedule resources in the same API response. The notebook sends the API Key in the `x-api-key` request header and calls `raise_for_status()` so HTTP request errors are raised rather than silently processed as valid data.

API authentication is handled through Azure Key Vault. The notebook retrieves the scret named `mbta-api-key` using `notebookutils.credentials.getSecret()`. This keeps the API key out of the notebook source code. The Key Vault URL, secret name, API endpoint, and route filter are defined in the configuration cell so they can be updated without changing the ingestion functions.

## Preparing the Bronze Records

The API response contains prediction objects in `data` and related entities in `included`. The notebook first creates a lookup of included schedule records by schedule ID. For every prediction, it reads the attributes and relationship references, including teh associated route, trip, stop, vehicle, and schedue. Where a matching schedule is present, the notebook adds selected schedule attributes to the same output record. If the schedule relationship is missing or its schedule record is not included, the corresponding schedule fields are left null.

This step convert the nested API response into records that can be loaded into a Spark DataFrame. It retains identifiers and operational attributes such as direction, stop sequence, predicted arrival and departure times, uncertainty values, predictio status, and trip headsign. It also captures the schedule ID, scheduled arrival and departure times, pickup and drop-off types, and timepoint indicator when available.

The notebook stores a `raw_json` column containing the original prediction object and its matched schedule object, if one is available. Keeping this source representation alongside the extracted columns supports tracebility and allows later transformations to refer back to the API payload. The `ingested_at` column records when the batch was prpared, using a UTC timestamp shared by the records from that API response.

## Schema and Lakehouse Write

Before loading the data, the notebook defines a PySpark `StructType` schema for the Bronze records. The schema specifies string, integer, Boolean, and timestamp types for the extracted fields. In particular, the prediction and scheduled arrival and departure values are retained as strings at ingestion; the notebook does not convert these source time values into Spark timestamps. The `raw_json` field is also stred as a string, while `ingested_at` uses `TimestampType`.

The notebook creates the `bronze` schema if it does not already exist, then builds a Spark DataFrame from the prepared records using teh explicit schema. It writes to `bronze.predictions_raw` with `df.write.mode("append").saveAsTable(table_name)`. Append mode adds the current response to the existing table rarther than replacing previously ingested records. The notebook returns the number of rows prepared and written for reporting in the execution log

This is an append based ingestion process, not an upsert or deduplication process. For transit sytems like MBTA, predictions are ingested in real-time as they appear, and the status, delays, arrival associated with a specific prediction ID change continuously. Downstream transformations must account for these multi-version records to extract the historical evolution of a trip.

## Execution Logging in Fabric Data Warehouse

The notebook writes an execution record to `WH_MBTA.control.pipeline_runs` using the Fabric Spark connector for Data Warehouse. It imports `com.microsoft.spark.fabric` and uses the `synapsesql()` writer with `mode("append")` to add a new audit record for each logged execution.

Each record contains a generated `run_id`, the stage name `bronze_predictions_ingest`, a status of `SUCCESS` or `FAILED`, the number of rows affected, execution start and completion timestamps, and an error message when an exception occurs. The `pipeline_run_id` field is included in the schema but is set to null in the current implementation. The run identifier and timestamps provide a way to distinguish individual notebook executions in the warehouse log.

The ingestion operations run inside a `try` block. When the API request, record preparation, and Lakehouse write complete successfully, the notebook writes a success log and prints the row count. If an exception occurs, it attempts to write a failure log with the error message, prints the failure, and raises teh exception again so the notebook execution is not reported as successful.

## Running the Notebook

The execution identity must be able to retrieve the configured Azure Key Vault secret, call the MBTA API, write to the `bronze` Lakehouse schema, and append to `WH_MBTA.control.pipeline_runs`.

Running teh notebook executes a single API ingestion request for the configured route filter. The final cell retrieves teh API key, fetches teh response, appends them to the Lakehouse table, and logs the execution outcome.

## Role in the Data Pipeline

`bronze.predictions_raw`  is the landing table for the prediction records retrievd by this notebook. It provides a consistent struture for downstream processing while retaining the JSON payload and ingestion metadat. The notebook is limited to source ingestion and Bronze storage.