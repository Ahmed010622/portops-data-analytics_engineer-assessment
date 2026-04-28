-- ============================================================
--  PortOps Data Mart  |  STAGING LAYER
--  Database : PortOps_Staging
--  Author   : Data & Analytics Engineer
--  Notes    : All columns VARCHAR / NVARCHAR to accept raw
--             Excel output exactly as-is.  SSIS performs
--             type coercion before loading the mart layer.
-- ============================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'PortOps_Staging')
BEGIN
    CREATE DATABASE PortOps_Staging;
END
GO

USE PortOps_Staging;
GO

-- ============================================================
--  SCHEMA
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'stg')
    EXEC sp_executesql N'CREATE SCHEMA stg';
GO

-- ============================================================
--  UTILITY : drop-and-recreate helper
--  Run this block first every time you re-run the script so
--  it is idempotent in both dev and CI environments.
-- ============================================================
IF OBJECT_ID('stg.vessel_calls',        'U') IS NOT NULL DROP TABLE stg.vessel_calls;
IF OBJECT_ID('stg.container_movements', 'U') IS NOT NULL DROP TABLE stg.container_movements;
IF OBJECT_ID('stg.gate_transactions',   'U') IS NOT NULL DROP TABLE stg.gate_transactions;
IF OBJECT_ID('stg.customers',           'U') IS NOT NULL DROP TABLE stg.customers;
IF OBJECT_ID('stg.customer_history',    'U') IS NOT NULL DROP TABLE stg.customer_history;
IF OBJECT_ID('stg.terminals',           'U') IS NOT NULL DROP TABLE stg.terminals;
IF OBJECT_ID('stg.equipment',           'U') IS NOT NULL DROP TABLE stg.equipment;
IF OBJECT_ID('stg.shifts',              'U') IS NOT NULL DROP TABLE stg.shifts;
IF OBJECT_ID('dbo.audit_log',           'U') IS NOT NULL DROP TABLE dbo.audit_log;
IF OBJECT_ID('dbo.error_table',         'U') IS NOT NULL DROP TABLE dbo.error_table;
GO

-- ============================================================
--  1. stg.vessel_calls
--     Source  : VesselCalls sheet  (~1,000 rows)
--     Grain   : One row per vessel call
--     Note    : eta / ata / atd arrive as Excel serial numbers
--               (FLOAT string) OR ISO datetime strings —
--               keep as NVARCHAR and convert in SSIS.
-- ============================================================
CREATE TABLE stg.vessel_calls
(
    stg_vessel_call_id      INT             IDENTITY(1,1)   NOT NULL,   -- surrogate for staging
    vessel_call_id          NVARCHAR(50)                        NULL,   -- source PK
    vessel_name             NVARCHAR(200)                       NULL,
    voyage_no               NVARCHAR(50)                        NULL,
    customer_id             NVARCHAR(50)                        NULL,
    terminal_id             NVARCHAR(50)                        NULL,
    eta                     NVARCHAR(50)                        NULL,   -- raw — may be float serial
    ata                     NVARCHAR(50)                        NULL,
    atd                     NVARCHAR(50)                        NULL,
    total_moves_planned     NVARCHAR(50)                        NULL,
    total_moves_actual      NVARCHAR(50)                        NULL,
    status                  NVARCHAR(50)                        NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_vessel_calls PRIMARY KEY (stg_vessel_call_id)
);
GO

-- ============================================================
--  2. stg.container_movements
--     Source  : ContainerMovements sheet  (~90,000 rows)
--     Grain   : One row per container move
-- ============================================================
CREATE TABLE stg.container_movements
(
    stg_movement_id         INT             IDENTITY(1,1)   NOT NULL,
    movement_id             NVARCHAR(50)                        NULL,
    vessel_call_id          NVARCHAR(50)                        NULL,
    container_id            NVARCHAR(50)                        NULL,
    container_size          NVARCHAR(20)                        NULL,   -- 20, 40, 45
    container_type          NVARCHAR(50)                        NULL,   -- Dry, Reefer, Tank, etc.
    move_type               NVARCHAR(50)                        NULL,   -- Discharge, Load, Shift
    customer_id             NVARCHAR(50)                        NULL,
    terminal_id             NVARCHAR(50)                        NULL,
    equipment_id            NVARCHAR(50)                        NULL,
    shift_id                NVARCHAR(50)                        NULL,
    move_start_time         NVARCHAR(50)                        NULL,   -- may be float serial
    move_end_time           NVARCHAR(50)                        NULL,
    move_date               NVARCHAR(50)                        NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_container_movements PRIMARY KEY (stg_movement_id)
);
GO

-- ============================================================
--  3. stg.gate_transactions
--     Source  : GateTransactions sheet  (~97,000 rows)
--     Grain   : One row per truck gate transaction
--     Note    : Both gate_in_time and gate_out_time must be
--               preserved — they map to TWO date FKs in the
--               fact table for the USERELATIONSHIP exercise.
-- ============================================================
CREATE TABLE stg.gate_transactions
(
    stg_gate_id             INT             IDENTITY(1,1)   NOT NULL,
    gate_transaction_id     NVARCHAR(50)                        NULL,
    customer_id             NVARCHAR(50)                        NULL,
    terminal_id             NVARCHAR(50)                        NULL,
    container_id            NVARCHAR(50)                        NULL,
    truck_id                NVARCHAR(100)                       NULL,
    gate_in_time            NVARCHAR(50)                        NULL,   -- raw datetime / serial
    gate_out_time           NVARCHAR(50)                        NULL,
    transaction_type        NVARCHAR(50)                        NULL,   -- Import / Export
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_gate_transactions PRIMARY KEY (stg_gate_id)
);
GO

-- ============================================================
--  4. stg.customers
--     Source  : Customers sheet  (12 rows — current state)
--     Note    : onboarded_date stored as Excel serial in source
-- ============================================================
CREATE TABLE stg.customers
(
    stg_customer_id         INT             IDENTITY(1,1)   NOT NULL,
    customer_id             NVARCHAR(50)                        NULL,
    customer_code           NVARCHAR(20)                        NULL,
    customer_name           NVARCHAR(200)                       NULL,
    country                 NVARCHAR(10)                        NULL,
    customer_tier           NVARCHAR(50)                        NULL,   -- Platinum/Gold/Silver/Bronze
    credit_limit            NVARCHAR(50)                        NULL,
    active_flag             NVARCHAR(10)                        NULL,
    onboarded_date          NVARCHAR(50)                        NULL,   -- raw serial
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_customers PRIMARY KEY (stg_customer_id)
);
GO

-- ============================================================
--  5. stg.customer_history
--     Source  : CustomerHistory sheet  (SCD Type 2 source)
--     Note    : effective_from / effective_to are Excel serials
--               except where effective_to = '9999-12-31' string
-- ============================================================
CREATE TABLE stg.customer_history
(
    stg_history_id          INT             IDENTITY(1,1)   NOT NULL,
    customer_id             NVARCHAR(50)                        NULL,
    effective_from          NVARCHAR(50)                        NULL,   -- may be serial or ISO date
    effective_to            NVARCHAR(50)                        NULL,   -- '9999-12-31' or serial
    customer_tier           NVARCHAR(50)                        NULL,
    credit_limit            NVARCHAR(50)                        NULL,
    change_reason           NVARCHAR(200)                       NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_customer_history PRIMARY KEY (stg_history_id)
);
GO

-- ============================================================
--  6. stg.terminals
--     Source  : Terminals sheet  (4 rows)
-- ============================================================
CREATE TABLE stg.terminals
(
    stg_terminal_id         INT             IDENTITY(1,1)   NOT NULL,
    terminal_id             NVARCHAR(50)                        NULL,
    terminal_code           NVARCHAR(20)                        NULL,
    terminal_name           NVARCHAR(200)                       NULL,
    zone                    NVARCHAR(50)                        NULL,
    terminal_type           NVARCHAR(100)                       NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_terminals PRIMARY KEY (stg_terminal_id)
);
GO

-- ============================================================
--  7. stg.equipment
--     Source  : Equipment sheet  (12 rows)
--     Note    : acquired_date is an Excel serial number
-- ============================================================
CREATE TABLE stg.equipment
(
    stg_equipment_id        INT             IDENTITY(1,1)   NOT NULL,
    equipment_id            NVARCHAR(50)                        NULL,
    equipment_code          NVARCHAR(50)                        NULL,
    equipment_type          NVARCHAR(100)                       NULL,
    terminal_id             NVARCHAR(50)                        NULL,
    capacity_tons           NVARCHAR(50)                        NULL,
    acquired_date           NVARCHAR(50)                        NULL,   -- raw serial
    status                  NVARCHAR(50)                        NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_equipment PRIMARY KEY (stg_equipment_id)
);
GO

-- ============================================================
--  8. stg.shifts
--     Source  : Shifts sheet  (3 rows)
--     Note    : start_time / end_time stored as HH:MM strings
-- ============================================================
CREATE TABLE stg.shifts
(
    stg_shift_id            INT             IDENTITY(1,1)   NOT NULL,
    shift_id                NVARCHAR(50)                        NULL,
    shift_code              NVARCHAR(10)                        NULL,
    shift_name              NVARCHAR(100)                       NULL,
    start_time              NVARCHAR(20)                        NULL,   -- e.g. '06:00'
    end_time                NVARCHAR(20)                        NULL,
    -- Pipeline metadata
    load_batch_id           INT                                 NULL,
    load_timestamp          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    source_file             NVARCHAR(500)                       NULL,
    is_valid                BIT             DEFAULT 1          NOT NULL,
    validation_message      NVARCHAR(1000)                      NULL,
    CONSTRAINT PK_stg_shifts PRIMARY KEY (stg_shift_id)
);
GO

-- ============================================================
--  AUDIT LOG
--  Every SSIS package writes one row at start (status = 'Running')
--  and updates it at end (status = 'Success' or 'Failed').
-- ============================================================
CREATE TABLE dbo.audit_log
(
    audit_id                INT             IDENTITY(1,1)   NOT NULL,
    batch_id                INT                             NOT NULL,   -- shared key across packages in one run
    package_name            NVARCHAR(200)                   NOT NULL,
    start_time              DATETIME2                       NOT NULL,
    end_time                DATETIME2                           NULL,
    status                  NVARCHAR(20)                    NOT NULL    -- Running / Success / Failed
                            CONSTRAINT CK_audit_status CHECK (status IN ('Running','Success','Failed')),
    rows_read_source        INT                                 NULL,
    rows_inserted_staging   INT                                 NULL,
    rows_inserted_target    INT                                 NULL,
    rows_rejected           INT                                 NULL,
    error_message           NVARCHAR(MAX)                       NULL,
    CONSTRAINT PK_audit_log PRIMARY KEY (audit_id)
);
GO

-- ============================================================
--  ERROR TABLE
--  Failed rows from every Lookup and Data Conversion component
--  land here rather than being silently discarded.
-- ============================================================
CREATE TABLE dbo.error_table
(
    error_id                INT             IDENTITY(1,1)   NOT NULL,
    batch_id                INT                             NOT NULL,
    package_name            NVARCHAR(200)                   NOT NULL,
    source_table            NVARCHAR(200)                   NOT NULL,
    error_column            NVARCHAR(200)                       NULL,
    error_code              INT                                 NULL,
    error_description       NVARCHAR(1000)                      NULL,
    raw_row                 NVARCHAR(MAX)                       NULL,   -- serialised source row for investigation
    logged_at               DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    CONSTRAINT PK_error_table PRIMARY KEY (error_id)
);
GO

PRINT 'PortOps_Staging: all staging objects created successfully.';
GO


--Create View
USE PortOps_Staging;
GO

CREATE OR ALTER VIEW stg.vw_customer_scd_source
AS
WITH history_clean AS
(
    SELECT
        CAST(h.customer_id AS INT)              AS customer_id,

        -- effective_from: may be Excel serial float OR ISO date string
        CASE
            WHEN ISNUMERIC(h.effective_from) = 1
            THEN CAST(
                    DATEADD(DAY,
                        CAST(CAST(h.effective_from AS FLOAT) AS INT) - 2,
                        CAST('1900-01-01' AS DATE))
                 AS DATE)
            ELSE TRY_CAST(h.effective_from AS DATE)
        END                                     AS effective_from,

        -- effective_to: may be serial, or the literal string '9999-12-31'
        CASE
            WHEN h.effective_to = '9999-12-31'  THEN CAST('9999-12-31' AS DATE)
            WHEN ISNUMERIC(h.effective_to) = 1
            THEN CAST(
                    DATEADD(DAY,
                        CAST(CAST(h.effective_to AS FLOAT) AS INT) - 2,
                        CAST('1900-01-01' AS DATE))
                 AS DATE)
            ELSE TRY_CAST(h.effective_to AS DATE)
        END                                     AS effective_to,

        LTRIM(RTRIM(h.customer_tier))           AS customer_tier,
        CAST(h.credit_limit AS DECIMAL(18,2))   AS credit_limit,
        LTRIM(RTRIM(h.change_reason))           AS change_reason
    FROM PortOps_Staging.stg.customer_history h
    WHERE h.is_valid = 1
),
current_attrs AS
(
    SELECT
        CAST(c.customer_id AS INT)              AS customer_id,
        LTRIM(RTRIM(c.customer_code))           AS customer_code,
        LTRIM(RTRIM(c.customer_name))           AS customer_name,
        LTRIM(RTRIM(c.country))                 AS country,
        CAST(c.active_flag AS BIT)              AS active_flag
    FROM PortOps_Staging.stg.customers c
    WHERE c.is_valid = 1
)
SELECT
    h.customer_id,
    c.customer_code,
    c.customer_name,
    c.country,
    c.active_flag,
    h.customer_tier,
    h.credit_limit,
    h.effective_from,
    h.effective_to,
    CASE WHEN h.effective_to = '9999-12-31' THEN 1 ELSE 0 END  AS is_current,
    h.change_reason
FROM history_clean   h
JOIN current_attrs   c ON c.customer_id = h.customer_id;
GO