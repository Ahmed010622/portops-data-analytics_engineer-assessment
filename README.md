# PortOps Data Mart — Submission README

## Candidate Information
- Assessment: Data & Analytics Engineer Technical Assessment
- Submission Date: April 2026

---

## Tool Versions Used

| Tool | Version |
|---|---|
| SQL Server | 2019 Developer Edition |
| SSMS | 19.x |
| Visual Studio | 2022 Community |
| SSIS (Integration Services Projects) | 4.x |
| Power BI Desktop | Latest (April 2026) |
| Microsoft Access Database Engine | 2016 (32-bit) |

---

## Setup Steps to Run This Submission

### Step 1 — Restore Databases
Run the DDL scripts in this exact order in SSMS:

```
part1_datamart/sql/01_staging_ddl.sql
part1_datamart/sql/02_mart_ddl.sql
```

Both databases will be created automatically:
- PortOps_Staging
- PortOps_Mart

### Step 2 — Run the Staging View
Run the view creation script:
```
part1_datamart/sql/03_staging_view.sql
```

### Step 3 — Open SSIS Solution
1. Open Visual Studio 2022
2. File → Open → Project/Solution
3. Select: part1_datamart/ssis/PortOps_DataMart.sln
4. Update the project parameter SourceFilePath to point to PortOps_SourceData.xlsx
5. Run pkg_master.dtsx

### Step 4 — Run SSMS INSERT Scripts (Fact Tables)
Because the fact table SQL Tasks use multi-step logic, run these directly in SSMS after the dimension packages complete:
```
part1_datamart/sql/fact_inserts/FINAL_insert_fact_vessel_call.sql
part1_datamart/sql/fact_inserts/FINAL_insert_fact_container_movement.sql
part1_datamart/sql/fact_inserts/FINAL_insert_fact_gate_transaction.sql
```

### Step 5 — Open Power BI Report
1. Open Power BI Desktop
2. File → Open → part2_powerbi/dashboard.pbix
3. Home → Transform data → Data source settings → update server name if needed
4. Refresh

---

## Assumptions Made

1. **Fiscal Year** starts 1 April — FY2025 covers April 2025 to March 2026. All fiscal attributes in dim_date are derived from this assumption.

2. **Excel serial dates** — all datetime columns in the source Excel file (eta, ata, atd, move_start_time, move_end_time, gate_in_time, gate_out_time) were stored as string datetime values (e.g. "2025-04-01 08:30:00"), not as Excel float serials. The SSIS and SQL logic handles both formats using ISNUMERIC() branching.

3. **move_date column** — the move_date column in the ContainerMovements sheet was entirely NULL in the source data. The date_key for fact_container_movement was therefore derived from move_start_time instead. This is documented in design_doc.md.

4. **SCD Type 2 customers** — based on the CustomerHistory sheet, four customers had tier or credit_limit changes during the period: customer_id 3 (CMA CGM), 6 (Evergreen), 8 (ZIM), and 11 (OOCL). All four have two rows in dim_customer reflecting their historical and current states.

5. **Unknown member** — all dimension surrogate keys use -1 as the default unknown member. Fact rows that cannot resolve a dimension FK are assigned -1 rather than being rejected, to preserve referential integrity and allow analysis of unclassified records.

6. **Validation tasks skipped** — the staging validation Execute SQL Tasks were removed from the SSIS packages due to OLE DB parser limitations with multi-statement SQL. Data quality is enforced instead through ISNUMERIC() guards and ISNULL() fallbacks in the INSERT SQL.

7. **gate_out_date_key** — rows where gate_out_time is NULL (trucks still inside terminal) are assigned gate_out_date_key = -1 (unknown member) rather than being excluded from the fact table.

---

## Written Question Answers

### Q1: Why did you choose a star schema over a snowflake schema?
A star schema was chosen because it optimises for query performance and Power BI compatibility. In a snowflake schema, dimension normalisation introduces additional joins that increase query complexity and reduce DAX measure performance due to expanded relationship chains. For a reporting layer serving a Power BI dashboard with slicers and cross-filtering, the denormalised star schema allows the VertiPaq engine to process filters efficiently. The slight increase in storage from denormalisation is negligible at this data volume (~190,000 fact rows) compared to the query performance gains.

### Q2: Explain your SCD Type 2 implementation and why you did not use the SSIS SCD Wizard.
The SCD Type 2 was implemented manually using a Lookup → Conditional Split → Multicast → OLE DB Command + OLE DB Destination pattern. The Lookup matches incoming rows against current dim_customer rows (is_current = 1). Matched rows flow into a Conditional Split that identifies changed rows (customer_tier or credit_limit differs). Changed rows are duplicated via Multicast: one path fires an OLE DB Command UPDATE to expire the old row (setting effective_to = new_effective_from - 1 day and is_current = 0), while the second path inserts the new version (is_current = 1, effective_to = 9999-12-31). The built-in SCD Wizard was avoided because: (1) it generates row-by-row OLEDB Commands that are extremely slow at scale, (2) it produces unreadable auto-generated XML, (3) it cannot handle mixed Type 1 and Type 2 attributes cleanly, and (4) it offers no error redirect support.

### Q3: How did you handle the two date foreign keys on fact_gate_transaction?
The fact_gate_transaction table has two date foreign keys: gate_in_date_key and gate_out_date_key. In the Power BI model, gate_in_date_key has the ACTIVE relationship to dim_date, which means all standard date-filtered measures (Gate-Ins Count) use the gate-in date automatically. The gate_out_date_key has an INACTIVE relationship to dim_date. The Gate-Outs Count DAX measure activates this relationship explicitly using USERELATIONSHIP(fact_gate_transaction[gate_out_date_key], dim_date[date_key]) inside a CALCULATE function. This pattern allows both date dimensions to be used independently in the same report without creating circular relationship conflicts.

### Q4: What data quality issues did you encounter and how did you handled them?
Three main issues were found. First, the move_date column in ContainerMovements was entirely NULL — resolved by deriving date_key from move_start_time instead, which contained valid datetime strings. Second, some CustomerHistory effective_from and effective_to dates were stored as Excel serial float numbers while others were ISO date strings — resolved using ISNUMERIC() branching in the staging view to handle both formats. Third, all datetime columns across all source sheets were stored as string datetimes rather than Excel serial numbers — all conversion logic was updated to use direct CAST(... AS DATETIME2) for string inputs. All unresolvable FK lookups default to -1 (unknown member) rather than causing row rejection.

### Q5: How did you ensure the SSIS packages are idempotent?
Every package begins by truncating its staging table and its corresponding mart fact table before loading. This ensures that re-running any package produces identical results regardless of how many times it has been executed. Dimension packages use MERGE statements (INSERT when not matched, UPDATE when matched) which are inherently idempotent — running them twice does not create duplicate rows. The dim_customer SCD2 package handles re-runs by checking is_current = 1 in the Lookup query, meaning already-expired rows are not re-processed.

### Q6: Describe the grain of each fact table.
fact_vessel_call: one row per vessel call, identified by vessel_call_id. Measures include berth_delay_hours, stay_hours, total_moves_planned, total_moves_actual, and moves_variance. fact_container_movement: one row per individual container move (discharge, load, or shift operation), identified by movement_id. The key measure is crane_cycle_seconds derived from move_start_time to move_end_time. fact_gate_transaction: one row per truck gate transaction, identified by gate_transaction_id. The key measure is truck_turnaround_minutes from gate_in_time to gate_out_time.

### Q7: Why did you store crane_cycle_seconds as an integer rather than computing it in DAX?
Storing the pre-computed value in the fact table follows the principle of moving computation as far upstream as possible. Computing DATEDIFF in SQL Server during the ETL load is a single set-based operation across 90,541 rows. Computing it in DAX would require storing raw datetime columns and running row-level calculations at query time for every visual refresh, filter change, and slicer interaction. Pre-aggregated integers also compress more efficiently in the VertiPaq columnar engine than datetime columns, reducing the in-memory model size.

### Q8: How does the SCD2 implementation affect the Power BI tier analysis visual?
Because fact rows are joined to dim_customer using surrogate keys (customer_sk) rather than natural keys (customer_id), each fact row is permanently associated with the dim_customer row that was current at the time of the move. When CMA CGM changed from Gold to Platinum tier mid-year, moves before the change retain the Gold surrogate key and moves after retain the Platinum surrogate key. The "Moves by Historical Customer Tier" visual on Page 3 therefore shows accurate split volumes across tiers — something that would be impossible with a Type 1 overwrite, which would retroactively reclassify all historical moves to the current tier.

### Q9: What would you change if this pipeline needed to run daily in production?
Five changes: (1) Replace TRUNCATE+INSERT with incremental loads using watermark columns (load_timestamp or a source last_modified date) to avoid reprocessing the entire dataset daily. (2) Add proper audit logging with row counts and execution times to a persistent audit table, with alerts on failure. (3) Parameterise the source file path and database connection strings through SSIS environment variables rather than hardcoded project parameters. (4) Add retry logic on Excel connection failures since file-based sources are unreliable in scheduled contexts — ideally migrate the source from Excel to a database or API. (5) Implement partition switching on the large fact tables (fact_container_movement at 90k+ rows will grow quickly) to allow efficient incremental appends without full table scans.
