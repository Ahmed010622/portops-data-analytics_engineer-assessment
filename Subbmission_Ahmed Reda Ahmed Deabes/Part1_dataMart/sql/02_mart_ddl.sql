-- ============================================================
--  PortOps Data Mart  |  MART LAYER
--  Database : PortOps_Mart
--  Author   : Data & Analytics Engineer
--
--  Star-schema objects:
--    Dimensions : dim_date, dim_customer (SCD2),
--                 dim_terminal, dim_equipment, dim_shift
--    Facts      : fact_container_movement,
--                 fact_vessel_call,
--                 fact_gate_transaction
--
--  Conventions:
--    • All dimension surrogate keys are INT; -1 = Unknown member
--    • All fact FKs reference surrogate keys, never natural keys
--    • Fiscal year starts 1 April  (FY2025 = Apr 2025 – Mar 2026)
-- ============================================================

USE master;
GO

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = N'PortOps_Mart')
BEGIN
    CREATE DATABASE PortOps_Mart;
END
GO

USE PortOps_Mart;
GO

-- ============================================================
--  SCHEMA
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'mart')
    EXEC sp_executesql N'CREATE SCHEMA mart';
GO

-- ============================================================
--  Drop existing objects (idempotent re-run)
--  Facts first to remove FK dependencies, then dimensions.
-- ============================================================
IF OBJECT_ID('mart.fact_container_movement', 'U') IS NOT NULL DROP TABLE mart.fact_container_movement;
IF OBJECT_ID('mart.fact_vessel_call',         'U') IS NOT NULL DROP TABLE mart.fact_vessel_call;
IF OBJECT_ID('mart.fact_gate_transaction',    'U') IS NOT NULL DROP TABLE mart.fact_gate_transaction;
IF OBJECT_ID('mart.dim_customer',             'U') IS NOT NULL DROP TABLE mart.dim_customer;
IF OBJECT_ID('mart.dim_terminal',             'U') IS NOT NULL DROP TABLE mart.dim_terminal;
IF OBJECT_ID('mart.dim_equipment',            'U') IS NOT NULL DROP TABLE mart.dim_equipment;
IF OBJECT_ID('mart.dim_shift',                'U') IS NOT NULL DROP TABLE mart.dim_shift;
IF OBJECT_ID('mart.dim_date',                 'U') IS NOT NULL DROP TABLE mart.dim_date;
GO


-- ============================================================
-- ============================================================
--  DIMENSIONS
-- ============================================================
-- ============================================================


-- ============================================================
--  dim_date
--  Type      : Static / reference
--  SCD Type  : N/A  (dates never change)
--  Range     : 1 April 2025 – 31 March 2026  (fiscal year)
--              + a 60-day buffer on each side for safety
--  Grain     : One row per calendar date
--  Key       : date_key  INT  YYYYMMDD  (e.g. 20250401)
-- ============================================================
CREATE TABLE mart.dim_date
(
    -- Surrogate key — integer YYYYMMDD for readable joins
    date_key                INT                             NOT NULL,

    -- Calendar attributes
    full_date               DATE                            NOT NULL,
    day_of_week             TINYINT                         NOT NULL,   -- 1=Sun … 7=Sat (DATEPART default)
    day_name                NVARCHAR(20)                    NOT NULL,   -- Monday … Sunday
    day_of_month            TINYINT                         NOT NULL,   -- 1–31
    day_of_year             SMALLINT                        NOT NULL,   -- 1–366
    week_of_year            TINYINT                         NOT NULL,   -- ISO week 1–53
    month_number            TINYINT                         NOT NULL,   -- 1–12
    month_name              NVARCHAR(20)                    NOT NULL,   -- January … December
    month_name_short        NCHAR(3)                        NOT NULL,   -- Jan … Dec
    quarter_number          TINYINT                         NOT NULL,   -- 1–4
    quarter_label           NCHAR(2)                        NOT NULL,   -- Q1 … Q4
    calendar_year           SMALLINT                        NOT NULL,
    calendar_year_month     INT                             NOT NULL,   -- YYYYMM e.g. 202504
    calendar_year_quarter   NVARCHAR(10)                    NOT NULL,   -- e.g. 2025-Q2

    -- Fiscal year attributes (FY starts 1 April)
    fiscal_year             SMALLINT                        NOT NULL,   -- FY2025 = Apr 2025 – Mar 2026
    fiscal_quarter          TINYINT                         NOT NULL,   -- 1–4  (Q1 = Apr–Jun)
    fiscal_month            TINYINT                         NOT NULL,   -- 1–12 (Month 1 = April)
    fiscal_year_label       NVARCHAR(10)                    NOT NULL,   -- e.g. 'FY2025'
    fiscal_quarter_label    NVARCHAR(10)                    NOT NULL,   -- e.g. 'FY2025-Q1'

    -- Flags
    is_weekend              BIT                             NOT NULL,
    is_weekday              BIT                             NOT NULL,
    is_last_day_of_month    BIT                             NOT NULL,

    CONSTRAINT PK_dim_date PRIMARY KEY (date_key)
);
GO

-- ============================================================
--  dim_date seed script
--  Populates 1 Feb 2025 – 31 May 2026  (reporting window
--  1 Apr 2025 – 31 Mar 2026 with 60-day buffer each end).
--  Re-running is safe because of the TRUNCATE guard.
-- ============================================================
IF NOT EXISTS (SELECT 1 FROM mart.dim_date WHERE date_key = 20250401)
BEGIN
    DECLARE @start  DATE = '2025-02-01';
    DECLARE @end    DATE = '2026-05-31';
    DECLARE @d      DATE = @start;

    WHILE @d <= @end
    BEGIN
        DECLARE @fy     SMALLINT = CASE WHEN MONTH(@d) >= 4 THEN YEAR(@d) ELSE YEAR(@d) - 1 END;
        DECLARE @fm     TINYINT  = CASE WHEN MONTH(@d) >= 4 THEN MONTH(@d) - 3 ELSE MONTH(@d) + 9 END;
        DECLARE @fq     TINYINT  = CEILING(@fm / 3.0);
        DECLARE @dow    TINYINT  = DATEPART(WEEKDAY, @d);  -- 1 Sun … 7 Sat

        INSERT INTO mart.dim_date
        (
            date_key, full_date,
            day_of_week, day_name, day_of_month, day_of_year, week_of_year,
            month_number, month_name, month_name_short,
            quarter_number, quarter_label,
            calendar_year, calendar_year_month, calendar_year_quarter,
            fiscal_year, fiscal_quarter, fiscal_month,
            fiscal_year_label, fiscal_quarter_label,
            is_weekend, is_weekday, is_last_day_of_month
        )
        VALUES
        (
            CAST(FORMAT(@d, 'yyyyMMdd') AS INT),
            @d,
            @dow,
            DATENAME(WEEKDAY, @d),
            DAY(@d),
            DATEPART(DAYOFYEAR, @d),
            DATEPART(WEEK, @d),
            MONTH(@d),
            DATENAME(MONTH, @d),
            LEFT(DATENAME(MONTH, @d), 3),
            DATEPART(QUARTER, @d),
            CONCAT('Q', DATEPART(QUARTER, @d)),
            YEAR(@d),
            CAST(FORMAT(@d, 'yyyyMM') AS INT),
            CONCAT(YEAR(@d), '-Q', DATEPART(QUARTER, @d)),
            @fy,
            @fq,
            @fm,
            CONCAT('FY', @fy),
            CONCAT('FY', @fy, '-Q', @fq),
            CASE WHEN @dow IN (1, 7) THEN 1 ELSE 0 END,
            CASE WHEN @dow IN (1, 7) THEN 0 ELSE 1 END,
            CASE WHEN @d = EOMONTH(@d)  THEN 1 ELSE 0 END
        );

        SET @d = DATEADD(DAY, 1, @d);
    END;

    PRINT 'dim_date seeded: ' + CAST(DATEDIFF(DAY, '2025-02-01', '2026-05-31') + 1 AS VARCHAR) + ' rows.';
END
GO


-- ============================================================
--  dim_customer
--  Type  : SCD Type 2 on customer_tier, credit_limit
--          SCD Type 1 on customer_name, customer_code,
--                        country, active_flag
--  Note  : Multiple rows per natural key (customer_id)
--          are valid — facts join on customer_sk
-- ============================================================
CREATE TABLE mart.dim_customer
(
    -- Surrogate key — -1 = Unknown/Late-arriving member
    customer_sk             INT             IDENTITY(1,1)   NOT NULL,

    -- Natural key
    customer_id            NVARCHAR(50)                            NOT NULL,

    -- Type 1 attributes (overwrite on change — no history kept)
    customer_code           NVARCHAR(20)                    NOT NULL,
    customer_name           NVARCHAR(200)                   NOT NULL,
    country                 NVARCHAR(10)                    NOT NULL,
    active_flag             BIT                             NOT NULL,

    -- Type 2 attributes (version history tracked)
    customer_tier           NVARCHAR(50)                    NOT NULL,   -- Platinum/Gold/Silver/Bronze
    credit_limit            DECIMAL(18, 2)                  NOT NULL,

    -- SCD2 control columns
    effective_from          DATE                            NOT NULL,
    effective_to            DATE                            NOT NULL    DEFAULT '9999-12-31',
    is_current              BIT                             NOT NULL    DEFAULT 1,
    change_reason           NVARCHAR(200)                       NULL,

    -- Audit
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    row_updated_at          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,

    CONSTRAINT PK_dim_customer PRIMARY KEY (customer_sk)
);
GO

-- Unknown member (-1) — every fact with no resolvable customer
-- points here rather than breaking referential integrity.
SET IDENTITY_INSERT mart.dim_customer ON;
INSERT INTO mart.dim_customer
(
    customer_sk, customer_id, customer_code, customer_name,
    country, active_flag, customer_tier, credit_limit,
    effective_from, effective_to, is_current, change_reason
)
VALUES
(
    -1, -1, 'UNKNOWN', 'Unknown Customer',
    'XX', 0, 'Unknown', 0,
    '1900-01-01', '9999-12-31', 1, 'Default unknown member'
);
SET IDENTITY_INSERT mart.dim_customer OFF;
GO

CREATE INDEX IX_dim_customer_nk      ON mart.dim_customer (customer_id);
CREATE INDEX IX_dim_customer_current ON mart.dim_customer (customer_id, is_current);
GO


-- ============================================================
--  dim_terminal
--  Type  : SCD Type 1 (overwrite on change)
-- ============================================================
CREATE TABLE mart.dim_terminal
(
    terminal_sk             INT             IDENTITY(1,1)   NOT NULL,
    terminal_id             INT                             NOT NULL,   -- natural key
    terminal_code           NVARCHAR(20)                    NOT NULL,
    terminal_name           NVARCHAR(200)                   NOT NULL,
    zone                    NVARCHAR(50)                    NOT NULL,
    terminal_type           NVARCHAR(100)                   NOT NULL,   -- Deep-Water / Feeder / RoRo
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    row_updated_at          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    CONSTRAINT PK_dim_terminal PRIMARY KEY (terminal_sk)
);
GO

SET IDENTITY_INSERT mart.dim_terminal ON;
INSERT INTO mart.dim_terminal (terminal_sk, terminal_id, terminal_code, terminal_name, zone, terminal_type)
VALUES (-1, -1, 'UNK', 'Unknown Terminal', 'Unknown', 'Unknown');
SET IDENTITY_INSERT mart.dim_terminal OFF;
GO

CREATE UNIQUE INDEX UIX_dim_terminal_nk ON mart.dim_terminal (terminal_id);
GO


-- ============================================================
--  dim_equipment
--  Type  : SCD Type 1
-- ============================================================
CREATE TABLE mart.dim_equipment
(
    equipment_sk            INT             IDENTITY(1,1)   NOT NULL,
    equipment_id            INT                             NOT NULL,   -- natural key
    equipment_code          NVARCHAR(50)                    NOT NULL,
    equipment_type          NVARCHAR(100)                   NOT NULL,   -- Ship-to-Shore Crane, RTG, etc.
    terminal_id             INT                             NOT NULL,   -- natural key reference
    capacity_tons           DECIMAL(10, 2)                      NULL,
    acquired_date           DATE                                NULL,
    status                  NVARCHAR(50)                    NOT NULL    DEFAULT 'Unknown',
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    row_updated_at          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    CONSTRAINT PK_dim_equipment PRIMARY KEY (equipment_sk)
);
GO

SET IDENTITY_INSERT mart.dim_equipment ON;
INSERT INTO mart.dim_equipment (equipment_sk, equipment_id, equipment_code, equipment_type, terminal_id, status)
VALUES (-1, -1, 'UNKNOWN', 'Unknown', -1, 'Unknown');
SET IDENTITY_INSERT mart.dim_equipment OFF;
GO

CREATE UNIQUE INDEX UIX_dim_equipment_nk ON mart.dim_equipment (equipment_id);
GO


-- ============================================================
--  dim_shift
--  Type  : SCD Type 1  (static — 3 rows in source)
-- ============================================================
CREATE TABLE mart.dim_shift
(
    shift_sk                INT             IDENTITY(1,1)   NOT NULL,
    shift_id                INT                             NOT NULL,   -- natural key
    shift_code              NCHAR(1)                        NOT NULL,   -- A / B / C
    shift_name              NVARCHAR(100)                   NOT NULL,
    start_time              TIME(0)                             NULL,
    end_time                TIME(0)                             NULL,
    crosses_midnight        BIT                             NOT NULL    DEFAULT 0,  -- Night shift flag
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    row_updated_at          DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,
    CONSTRAINT PK_dim_shift PRIMARY KEY (shift_sk)
);
GO

SET IDENTITY_INSERT mart.dim_shift ON;
INSERT INTO mart.dim_shift (shift_sk, shift_id, shift_code, shift_name, crosses_midnight)
VALUES (-1, -1, 'U', 'Unknown Shift', 0);
SET IDENTITY_INSERT mart.dim_shift OFF;
GO

CREATE UNIQUE INDEX UIX_dim_shift_nk ON mart.dim_shift (shift_id);
GO


-- ============================================================
-- ============================================================
--  FACTS
-- ============================================================
-- ============================================================


-- ============================================================
--  fact_container_movement
--  Grain : One row per container move
--  Measures :
--    move_count            -- additive (COUNT via fact rows)
--    crane_cycle_seconds   -- derived: DATEDIFF(SECOND, start, end)
-- ============================================================
CREATE TABLE mart.fact_container_movement
(
    movement_sk             BIGINT          IDENTITY(1,1)   NOT NULL,

    -- Dimension foreign keys (surrogate)
    date_key                INT                             NOT NULL    DEFAULT -1,
    customer_sk             INT                             NOT NULL    DEFAULT -1,
    terminal_sk             INT                             NOT NULL    DEFAULT -1,
    equipment_sk            INT                             NOT NULL    DEFAULT -1,
    shift_sk                INT                             NOT NULL    DEFAULT -1,
    vessel_call_sk          BIGINT                              NULL,   -- FK to fact_vessel_call (degenerate bridge)

    -- Degenerate dimensions (source identifiers kept for drill-through)
    movement_id             INT                                 NULL,
    container_id            NVARCHAR(50)                        NULL,
    container_size          NVARCHAR(20)                        NULL,   -- 20 / 40 / 45
    container_type          NVARCHAR(50)                        NULL,   -- Dry / Reefer / Tank / OOG
    move_type               NVARCHAR(50)                        NULL,   -- Discharge / Load / Shift

    -- Measures
    crane_cycle_seconds     INT                                 NULL,   -- move_end - move_start in seconds
                                                                        -- NULL if either timestamp missing
    -- Raw timestamps — useful for Power BI drill-down
    move_start_datetime     DATETIME2                           NULL,
    move_end_datetime       DATETIME2                           NULL,

    -- Audit
    load_batch_id           INT                                 NULL,
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,

    CONSTRAINT PK_fact_container_movement PRIMARY KEY (movement_sk),

    -- Referential integrity to dimensions
    CONSTRAINT FK_fcm_date      FOREIGN KEY (date_key)      REFERENCES mart.dim_date      (date_key),
    CONSTRAINT FK_fcm_customer  FOREIGN KEY (customer_sk)   REFERENCES mart.dim_customer  (customer_sk),
    CONSTRAINT FK_fcm_terminal  FOREIGN KEY (terminal_sk)   REFERENCES mart.dim_terminal  (terminal_sk),
    CONSTRAINT FK_fcm_equipment FOREIGN KEY (equipment_sk)  REFERENCES mart.dim_equipment (equipment_sk),
    CONSTRAINT FK_fcm_shift     FOREIGN KEY (shift_sk)      REFERENCES mart.dim_shift     (shift_sk)
);
GO

-- Indexes to support common Power BI filter patterns
CREATE INDEX IX_fcm_date         ON mart.fact_container_movement (date_key);
CREATE INDEX IX_fcm_customer     ON mart.fact_container_movement (customer_sk);
CREATE INDEX IX_fcm_terminal     ON mart.fact_container_movement (terminal_sk);
CREATE INDEX IX_fcm_shift        ON mart.fact_container_movement (shift_sk);
CREATE INDEX IX_fcm_move_type    ON mart.fact_container_movement (move_type);
GO


-- ============================================================
--  fact_vessel_call
--  Grain : One row per vessel call
--  Measures :
--    berth_delay_hours     -- ATA - ETA  (negative = arrived early)
--    stay_hours            -- ATD - ATA
--    moves_variance        -- total_moves_actual - total_moves_planned
--    total_moves_planned
--    total_moves_actual
-- ============================================================
CREATE TABLE mart.fact_vessel_call
(
    vessel_call_sk          BIGINT          IDENTITY(1,1)   NOT NULL,

    -- Dimension foreign keys (surrogate)
    date_key                INT                             NOT NULL    DEFAULT -1,   -- ATA date
    customer_sk             INT                             NOT NULL    DEFAULT -1,
    terminal_sk             INT                             NOT NULL    DEFAULT -1,

    -- Degenerate dimensions
    vessel_call_id          INT                                 NULL,
    vessel_name             NVARCHAR(200)                       NULL,
    voyage_no               NVARCHAR(50)                        NULL,
    status                  NVARCHAR(50)                        NULL,

    -- Timestamps (stored for drill-down)
    eta_datetime            DATETIME2                           NULL,
    ata_datetime            DATETIME2                           NULL,
    atd_datetime            DATETIME2                           NULL,

    -- Derived measures
    berth_delay_hours       DECIMAL(10, 4)                      NULL,   -- (ATA - ETA) in hours
    stay_hours              DECIMAL(10, 4)                      NULL,   -- (ATD - ATA) in hours
    total_moves_planned     INT                                 NULL,
    total_moves_actual      INT                                 NULL,
    moves_variance          INT                                 NULL,   -- actual - planned

    -- Audit
    load_batch_id           INT                                 NULL,
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,

    CONSTRAINT PK_fact_vessel_call PRIMARY KEY (vessel_call_sk),

    CONSTRAINT FK_fvc_date      FOREIGN KEY (date_key)      REFERENCES mart.dim_date     (date_key),
    CONSTRAINT FK_fvc_customer  FOREIGN KEY (customer_sk)   REFERENCES mart.dim_customer (customer_sk),
    CONSTRAINT FK_fvc_terminal  FOREIGN KEY (terminal_sk)   REFERENCES mart.dim_terminal (terminal_sk)
);
GO

CREATE INDEX IX_fvc_date        ON mart.fact_vessel_call (date_key);
CREATE INDEX IX_fvc_customer    ON mart.fact_vessel_call (customer_sk);
CREATE INDEX IX_fvc_terminal    ON mart.fact_vessel_call (terminal_sk);
GO


-- ============================================================
--  fact_gate_transaction
--  Grain : One row per truck gate transaction
--
--  TWO date foreign keys are required:
--    gate_in_date_key   → active   relationship in Power BI
--    gate_out_date_key  → inactive relationship (activated via
--                         USERELATIONSHIP in DAX measures)
--
--  Measures :
--    truck_turnaround_minutes  -- gate_out - gate_in in minutes
-- ============================================================
CREATE TABLE mart.fact_gate_transaction
(
    gate_transaction_sk     BIGINT          IDENTITY(1,1)   NOT NULL,

    -- Dimension foreign keys (surrogate)
    gate_in_date_key        INT                             NOT NULL    DEFAULT -1,   -- ACTIVE relationship
    gate_out_date_key       INT                             NOT NULL    DEFAULT -1,   -- INACTIVE relationship
    customer_sk             INT                             NOT NULL    DEFAULT -1,
    terminal_sk             INT                             NOT NULL    DEFAULT -1,

    -- Degenerate dimensions
    gate_transaction_id     INT                                 NULL,
    container_id            NVARCHAR(50)                        NULL,
    truck_id                NVARCHAR(100)                       NULL,
    transaction_type        NVARCHAR(50)                        NULL,   -- Import / Export

    -- Timestamps
    gate_in_datetime        DATETIME2                           NULL,
    gate_out_datetime       DATETIME2                           NULL,

    -- Derived measure
    truck_turnaround_minutes DECIMAL(10, 2)                     NULL,   -- gate_out - gate_in in minutes

    -- Audit
    load_batch_id           INT                                 NULL,
    row_inserted_at         DATETIME2       DEFAULT SYSDATETIME()  NOT NULL,

    CONSTRAINT PK_fact_gate_transaction PRIMARY KEY (gate_transaction_sk),

    -- Active relationship  (Power BI default)
    CONSTRAINT FK_fgt_gate_in_date   FOREIGN KEY (gate_in_date_key)  REFERENCES mart.dim_date (date_key),

    -- Inactive relationship  (USERELATIONSHIP in DAX)
    CONSTRAINT FK_fgt_gate_out_date  FOREIGN KEY (gate_out_date_key) REFERENCES mart.dim_date (date_key),

    CONSTRAINT FK_fgt_customer       FOREIGN KEY (customer_sk)       REFERENCES mart.dim_customer (customer_sk),
    CONSTRAINT FK_fgt_terminal       FOREIGN KEY (terminal_sk)       REFERENCES mart.dim_terminal (terminal_sk)
);
GO

CREATE INDEX IX_fgt_gate_in_date  ON mart.fact_gate_transaction (gate_in_date_key);
CREATE INDEX IX_fgt_gate_out_date ON mart.fact_gate_transaction (gate_out_date_key);
CREATE INDEX IX_fgt_customer      ON mart.fact_gate_transaction (customer_sk);
CREATE INDEX IX_fgt_terminal      ON mart.fact_gate_transaction (terminal_sk);
GO


-- ============================================================
--  HELPER VIEW  (optional — useful for SSIS Lookup sources)
--  Returns only the current dim_customer row per natural key,
--  to resolve natural-key → surrogate-key lookups on live loads
-- ============================================================
CREATE OR ALTER VIEW mart.vw_dim_customer_current
AS
SELECT
    customer_sk,
    customer_id,
    customer_code,
    customer_name,
    customer_tier,
    credit_limit,
    effective_from,
    effective_to
FROM mart.dim_customer
WHERE is_current = 1;
GO


-- ============================================================
--  VERIFY OBJECT COUNT
-- ============================================================
SELECT
    SCHEMA_NAME(schema_id)  AS [schema],
    name                    AS object_name,
    type_desc
FROM sys.objects
WHERE schema_id = SCHEMA_ID('mart')
  AND type IN ('U', 'V')
ORDER BY type_desc, name;
GO

PRINT 'PortOps_Mart: all mart objects created successfully.';
GO
