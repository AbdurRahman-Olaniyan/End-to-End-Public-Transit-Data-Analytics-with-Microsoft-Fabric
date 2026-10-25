CREATE TABLE silver.predictions (
    prediction_id              VARCHAR(200)   NOT NULL,
    route_id                   VARCHAR(20)    NULL,
    route_long_name            VARCHAR(100)   NULL,
    trip_id                    VARCHAR(50)    NULL,
    trip_headsign               VARCHAR(100)   NULL,
    stop_id                    VARCHAR(20)    NULL,
    stop_name                   VARCHAR(100)   NULL,
    direction_id                INT            NULL,
    is_revenue_trip             BIT            NOT NULL,
    predicted_departure_time    DATETIME2(6)   NULL,
    scheduled_departure_time    DATETIME2(6)   NULL,
    delay_minutes                INT           NULL,
    ingested_at                 DATETIME2(6)   NOT NULL
);
GO

ALTER TABLE silver.predictions
ADD CONSTRAINT PK_silver_predictions PRIMARY KEY NONCLUSTERED (prediction_id) NOT ENFORCED;
GO