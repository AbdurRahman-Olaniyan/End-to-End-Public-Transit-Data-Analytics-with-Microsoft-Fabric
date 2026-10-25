-- wawatermark
CREATE TABLE control.watermark (
    source_name                VARCHAR(100)   NOT NULL,
    watermark_value            DATETIME2(6)   NOT NULL,
    last_run_at                DATETIME2(6)   NULL,
    rows_processed_last_run    INT            NULL
);
GO

ALTER TABLE control.watermark
ADD CONSTRAINT PK_watermark PRIMARY KEY NONCLUSTERED (source_name) NOT ENFORCED;
GO

INSERT INTO control.watermark (source_name, watermark_value, last_run_at, rows_processed_last_run)
VALUES ('predictions_red_line', '1900-01-01 00:00:00', NULL, NULL);
GO

-- pipeline_runs
CREATE TABLE control.pipeline_runs (
    run_id           VARCHAR(36)    NOT NULL,
    pipeline_run_id  VARCHAR(100)   NULL,
    stage_name       VARCHAR(50)    NOT NULL,
    status           VARCHAR(20)    NOT NULL,
    rows_affected    INT            NULL,
    started_at       DATETIME2(6)   NOT NULL,
    completed_at     DATETIME2(6)   NULL,
    error_message    VARCHAR(4000)  NULL
);
GO