# PortOps Data Mart — Design Document

## 1. Architecture Overview

The solution follows a two-layer architecture:

```
Source (Excel)
    ↓ SSIS
PortOps_Staging  (stg schema)
    ↓ SSIS / SQL
PortOps_Mart     (mart schema)
    ↓ Power BI Import
Dashboard (3 pages)
```

The staging layer acts as a raw landing zone — all columns are NVARCHAR to accept Excel output exactly as-is with no transformation. The mart layer contains fully typed, surrogate-keyed star-schema objects. All transformation logic runs between staging and mart.

---

## 2. Star Schema Design

### Dimensions

| Table | SCD Type | Natural Key | Notes |
|---|---|---|---|
| dim_date | Static | date_key (YYYYMMDD INT) | Seeded in SQL, fiscal year starts 1 April |
| dim_customer | Type 2 (tier, credit_limit) + Type 1 (name, code, country, active_flag) | customer_id | 16 rows for 12 customers (4 have 2 versions) |
| dim_terminal | Type 1 | terminal_id | 4 rows |
| dim_equipment | Type 1 | equipment_id | 12 rows |
| dim_shift | Type 1 | shift_id | 3 rows (Day/Evening/Night) |

### Facts

| Table | Grain | Rows | Key Measures |
|---|---|---|---|
| fact_vessel_call | One per vessel call | ~1,076 | berth_delay_hours, stay_hours, moves_variance |
| fact_container_movement | One per container move | ~90,541 | crane_cycle_seconds |
| fact_gate_transaction | One per truck gate transaction | ~97,000 | truck_turnaround_minutes |

### Unknown Member Convention
Every dimension has a -1 surrogate key row with description "Unknown". All fact FKs that cannot resolve a dimension lookup default to -1. This preserves referential integrity without rejecting rows and allows analysis of unclassified records separately.

---

## 3. dim_date Design

The date dimension covers 1 February 2025 to 31 May 2026 — a 60-day buffer beyond the reporting window on each side to handle edge cases (vessels with ETA before April or ATD after March).

Fiscal year attributes follow the 1 April start convention:
- FY2025 = 1 April 2025 to 31 March 2026
- Fiscal Month 1 = April, Month 12 = March
- Fiscal Quarter 1 = April–June

The date_key is an integer in YYYYMMDD format (e.g. 20250401) rather than a DATE surrogate for two reasons: integer joins are faster than date joins in SQL Server, and YYYYMMDD integers are human-readable for debugging.

---

## 4. SCD Type 2 Implementation

### Pattern Used
Manual Lookup → Conditional Split → Multicast → expire + insert

### Type 2 Attributes (versioned)
- customer_tier
- credit_limit

### Type 1 Attributes (overwrite in place)
- customer_name
- customer_code
- country
- active_flag

### Process Flow
1. Source view (stg.vw_customer_scd_source) joins CustomerHistory and Customers sheets, converting all dates from either Excel serial float or ISO string format
2. Lookup matches incoming rows against dim_customer WHERE is_current = 1
3. No-match rows → insert as new customer (first-time load)
4. Match rows → Conditional Split checks if customer_tier or credit_limit changed
5. Changed rows → Multicast duplicates the stream:
   - Path 1: OLE DB Command UPDATE sets effective_to = new_effective_from - 1 day, is_current = 0
   - Path 2: OLE DB Destination INSERT creates new row with is_current = 1, effective_to = 9999-12-31
6. After Data Flow: Execute SQL Task applies Type 1 overwrites to ALL rows for each customer

### Customers with 2 Versions (SCD2 Changes)
- Customer 3 (CMA CGM): Gold → Platinum
- Customer 6 (Evergreen): Silver → Gold
- Customer 8 (ZIM): Silver → Bronze
- Customer 11 (OOCL): Bronze → Silver

---

## 5. fact_gate_transaction — Dual Date FK Design

This fact table has two date foreign keys:

```
gate_in_date_key  → dim_date[date_key]   ACTIVE relationship
gate_out_date_key → dim_date[date_key]   INACTIVE relationship
```

Power BI only allows one active relationship between any two tables. The inactive relationship is activated on-demand in DAX using USERELATIONSHIP():

```dax
Gate-Outs Count =
CALCULATE(
    COUNTROWS(fact_gate_transaction),
    USERELATIONSHIP(fact_gate_transaction[gate_out_date_key], dim_date[date_key])
)
```

Rows where gate_out_time is NULL (trucks still inside terminal) are assigned gate_out_date_key = -1 to preserve the row in the fact table without a broken FK reference.

---

## 6. Data Quality Findings

### Issue 1: move_date column entirely NULL
Source: ContainerMovements sheet
Impact: date_key for fact_container_movement could not be derived from move_date
Resolution: date_key derived from move_start_time instead (CAST to DATE, formatted as YYYYMMDD)

### Issue 2: DateTime columns stored as strings not Excel serials
Source: All sheets
Impact: Serial-to-datetime conversion formula produced no results
Resolution: All date conversion logic updated to CAST(... AS DATETIME2) for string inputs, with ISNUMERIC() branching to handle both formats

### Issue 3: CustomerHistory dates mixed format
Source: CustomerHistory sheet
Impact: effective_from and effective_to in some rows were Excel serial floats, in others ISO date strings, and effective_to = '9999-12-31' as literal string
Resolution: staging view (stg.vw_customer_scd_source) uses CASE WHEN ISNUMERIC() THEN serial conversion ELSE TRY_CAST AS DATE END

### Issue 4: transaction_type NULL in some gate transaction rows
Source: GateTransactions sheet
Resolution: Column mapping verified in OLE DB Destination Mappings tab. LTRIM(RTRIM()) applied in INSERT to clean whitespace.

---

## 7. SSIS Package Architecture

```
pkg_master.dtsx
├── SCR - Generate BatchId
├── EPT - pkg_dim_terminal
├── EPT - pkg_dim_equipment
├── EPT - pkg_dim_shift
├── EPT - pkg_dim_customer      ← SCD Type 2
├── EPT - pkg_fact_vessel_call
├── EPT - pkg_fact_container_movement
└── EPT - pkg_fact_gate_transaction
```

All packages are connected with Success precedence constraints. Dimensions always load before facts. The BatchId script task generates a unique integer for each master run by querying MAX(batch_id) + 1 from audit_log.

### Control Flow Pattern (each fact package)
```
SQL - Truncate stg.*
    ↓
SQL - Truncate mart.fact_*
    ↓
DFT - Load stg.* from Excel
    ↓
SQL - INSERT into mart fact table
```

---

## 8. Scalability Trade-offs

### Current Approach (suitable for assessment)
- Full truncate and reload on every run
- Single-threaded SSIS execution
- No partitioning on fact tables
- File-based Excel source

### Production Recommendations
- Incremental loads using watermark columns to avoid full reprocessing
- Partition switching on fact_container_movement (largest table, will grow quickly)
- Migrate source from Excel to SQL database or API to remove file-locking risks
- Parallel fact package execution (packages 5-7 have no interdependencies and could run concurrently)
- Add columnstore indexes on fact tables for analytical query performance
- Implement proper error alerting via SQL Server Agent job notifications

---

## 9. Power BI Model Design

### Import vs DirectQuery
Import mode was chosen for performance. At ~190,000 fact rows the dataset fits comfortably in memory and Import allows VertiPaq compression to reduce model size significantly.

### Relationship Architecture
12 relationships total — all Many-to-One from fact to dimension, single-direction cross-filter. The one exception is fact_gate_transaction which has two relationships to dim_date (active + inactive as described above).

### DAX Measure Design Principles
- All measures use DIVIDE() instead of division operator to handle divide-by-zero gracefully
- FILTER() used instead of WHERE for semi-additive measures to preserve filter context
- Time intelligence measures (YoY, rolling average) rely on dim_date being marked as date table
