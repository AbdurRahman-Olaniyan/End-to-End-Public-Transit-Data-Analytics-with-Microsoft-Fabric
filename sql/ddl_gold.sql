CREATE TABLE gold.dim_route (
    route_id        VARCHAR(20)    NOT NULL,
    route_long_name VARCHAR(100)   NULL,
    route_key       BIGINT         NULL
);
GO
ALTER TABLE gold.dim_route ADD CONSTRAINT PK_dim_route PRIMARY KEY NONCLUSTERED (route_id) NOT ENFORCED;
GO

CREATE TABLE gold.dim_stop (
    stop_id     VARCHAR(20)    NOT NULL,
    stop_name   VARCHAR(100)   NULL,
    stop_key    BIGINT         NULL
);
GO
ALTER TABLE gold.dim_stop ADD CONSTRAINT PK_dim_stop PRIMARY KEY NONCLUSTERED (stop_id) NOT ENFORCED;
GO

CREATE TABLE gold.dim_trip (
    trip_id         VARCHAR(50)    NOT NULL,
    trip_headsign   VARCHAR(100)   NULL,
    direction_id    INT            NULL,
    trip_key        BIGINT         NULL
);
GO
ALTER TABLE gold.dim_trip ADD CONSTRAINT PK_dim_trip PRIMARY KEY NONCLUSTERED (trip_id) NOT ENFORCED;
GO

CREATE TABLE gold.fact_predictions (
    prediction_id             VARCHAR(200)   NOT NULL,
    route_id                  VARCHAR(20)    NULL,
    stop_id                   VARCHAR(20)    NULL,
    trip_id                   VARCHAR(50)    NULL,
    predicted_departure_time DATETIME2(6)   NULL,
    scheduled_departure_time DATETIME2(6)   NULL,
    delay_minutes             INT            NULL,
    ingested_at               DATETIME2(6)   NOT NULL,
    route_key                 BIGINT         NULL,
    stop_key                  BIGINT         NULL,
    trip_key                  BIGINT         NULL,
    date_key                  INT            NULL,
    departure_hour            INT            NULL,
    delay_band                VARCHAR(20)    NULL,
    delay_band_sort           INT            NULL
);
GO
ALTER TABLE gold.fact_predictions ADD CONSTRAINT PK_fact_predictions PRIMARY KEY NONCLUSTERED (prediction_id) NOT ENFORCED;
GO

CREATE TABLE gold.dim_date
(
    date_key INT,
    full_date DATE,
    year_number INT,
    quarter_number INT,
    quarter_name VARCHAR(2),
    month_number INT,
    month_name VARCHAR(20),
    month_short VARCHAR(3),
    year_month VARCHAR(7),
    year_month_sort INT,
    week_number INT,
    week_start DATE,
    day_of_month INT,
    day_of_year INT,
    day_of_week INT,
    day_name VARCHAR(20),
    day_type VARCHAR(10),
    is_weekend BIT
);