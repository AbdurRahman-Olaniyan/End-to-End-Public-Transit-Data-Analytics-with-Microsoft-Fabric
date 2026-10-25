# Reference Data Ingestion

## Overview

The `reference_ingest_bronze` notebook ingests route, stop, and trip reference data from the MBTA V3 API into Microsoft Fabric Lakehouse. It is part of the Bronze ingestion layer off the MBTA data pipeline, where API responses are captured and stored as Delta tables for downstream processing. The notebook focuses on the Red Line and loads the three datasets into separate Lakehouse tables: `bronze.route_raw`, `bronze.stops_raw`, and `bronze.trips_raw`.

The route, stop, and trip records descrie the transit network and its services. The notebook refreshes these reference datasets using overwrite mode, so each successful table write replaces the previous contents with the records returned by that ingestion run. The datasets can then be used in later processing to provide context for prediction data, such as stop locations and trip direction information.

## Source Configuration and Authentication

The notebook uses the MBTA V3 API as its source. A `ROUTE_FILTER` value of `Red` scopes the requests to the Red Line. Separate requests are made to the `/routes`, `/stops`, and `/trips` endpoints. At execution time, `notebookutils.credentials.getSecret()` retrieves the secret from the configured vault and makes it available for the API requests. The key is then supplied through the `x-api-key` request header. This keeps the credential separate from the ingestion logic and supports secure credential management in the Fabric environment.

## Extracting Reference Data

The route ingestion calls the `/routes` endpoint with `filter[id]=Red`. It reads the returned route resources and extracts information such as the route identifier, short and long names, description, display colors, route type, sort order, and direction details.

The stop ingestion calls the `/stops` endpoint with `filter[route]=Red` and `include=child_stops`. Including child stops allows the response to contain both the stop resources returned in the primary `data` collection and related child-stop resources in the `included` collection. The notebook combines the two collections, retains only resources with the `stop` type, and removes duplicate stop IDs before preparing the records for Spark. This provides a single set of stop records covering the resources available in that API response.

The trip ingestion calls the `/trips` endpoint with `filter[route]=Red`. It extracts trip identifiers and service attributes, including the headsign, name, direction, block identifier, wheelchair accessibility, and bicycle allowance. The associated `route_id` is taken from the trip's `relationships.route.data` reference rather than from its attributes.

## Preparing Data with PySpark

Each source has its own transformation function and an explicitly defined PySpark `StructType` schema. The transformation functions read the MBTA JSON resources and map selected nested fields into named columns. The schemas specify the column names and data types used when the records are converted into Spark DataFrames, including strings, integers, doubles, and timestamps.

For all three datasets, the notebook stores the complete individual API resource in a `raw_json` column using `json.dumps()`. This preserves the original resource content alongside the extracted columns and provides a way to inspect fields that are not separately mapped. Each record is also assigned an `ingested_at` timestamp in UTC. The timestamp is created during the transformation step and records when that batch of source records was prepared for ingestion.

## Writing to the Fabric Lakehouse

The notebook uses a shared `write_to_bronze()` function to create a Spark DataFrame from the prepared rows and source-specific schema. It then writes the DataFrame to a managed Lakehouse table through `saveAsTable()`.

The three target tables are `bronze.routes_raw`, `bronze.stops_raw`, and `bronze.trips_raw`. Each write explicitly uses `mode("overwrite")`. This is intentional for these reference datasets: on a successful write, the table is refreshed with the records available in the current extraction rather than accumulating another copy of the same source records on each execution.

## Execution Flow and Audit Logging

The notebook uses `run_reference_ingest()` to apply the same execution pattern to each reference source. The function receives the source name, API extraction function, transformation function, Spark schema, and destination table name. For each source, it records a UTC start time, fetches the API response, prepares the rows, writes the Bronze table, and records the number of rows processed.

Execution details are written to the `WH_MBTA.control.pipeline_runs` table in a Fabric Data Warehouse. The audit records are created as Spark DataFrames and written using the Fabric Warehouse connector through `synapsesql()`, with `mode("append")` explicitly set. This appends a new audit record for each logged execution without replacing previous log entries.

Each audit record contains a generated `run_id`, the stage name, execution status, row count, start and completion timestamps, and an optional error message. The `pipeline_run_id` field is present in the audit schema but is set to `None` by this notebook. Successful executions are recorded with `SUCCESS`; when an exception occurs, the notebook attempts to record `FAILED` with a row count of zero and the exception message, then raises the error again. This makes the failure visible to the caller rather than silently continuing.

At the end of the notebook, the API key is retrieved once and the three ingestion stages run sequentially: `bronze_routes_ingest`, `bronze_stops_ingest`, and `bronze_trips_ingest`. Because the stages run in that order and failures are re-raised, an unhandled failure in an earlier stage prevents later stages from running in that execution. The audit table therefore records the stages that were actually attempted, not necessarily all three on every run.

## Role in the Data Pipeline

This notebook establishes the Bronze reference tables used by the broader MBTA analytics pipeline. The Lakehouse retains both the extracted source attributes and each resource's original JSON, while the Warehouse audit table records operational information about ingestion runs. Keeping source data and execution metadata in separate destinations helps distinguish data processing from pipeline monitoring.

The notebook's responsibility ends at ingestion and Bronze storage. The reference tables provide the source-aligned route, stop, and trip data needed to support those later transformations.