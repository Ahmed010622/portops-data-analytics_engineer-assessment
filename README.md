
# PortOps DataMart Submission

## Candidate Information

Name: Ahmed Reda Deabes

Submission: PortOps Data Engineering Assessment


---

## Project Overview

This project implements a complete data pipeline and analytical reporting solution for port operations.

The solution includes:

1. ETL pipelines using SSIS
2. Staging and Data Mart layers in SQL Server
3. Slowly Changing Dimension (SCD Type 2)
4. Data quality validation
5. Error logging
6. Power BI dashboards


---

## Technology Stack

### Database
- Microsoft SQL Server

### ETL Tool
- SQL Server Integration Services (SSIS)

### Reporting
- Power BI Desktop

### Source Format
- Excel files


---

## Tool Versions

SQL Server: 2019

SSIS: Visual Studio + SSDT

Power BI Desktop: Latest version


---

## Project Structure

submission_AhmedRedaDeabes.zip

part1_datamart/
- ssis/
- sql/
- design_doc.md
- screenshots/

part2_powerbi/
- dashboard.pbix
- dax_measures.md
- screenshots/


---

## Setup Steps

## 1. Create Databases

Create:

- PortOps_Staging
- PortOps_Mart


## 2. Run SQL Scripts

Execution order:

1. create_staging_tables.sql
2. create_dimension_tables.sql
3. create_fact_tables.sql
4. create_views.sql
5. validation_rules.sql


## 3. Open SSIS Solution

Open the solution file inside:

part1_datamart/ssis/


## 4. Configure Connections

Update:

- Excel source paths
- SQL Server connection strings


## 5. Execute Packages

Execution order:

1. Load staging packages
2. Validate staging
3. Load dimensions
4. Load facts


## 6. Open Power BI Dashboard

Open:

part2_powerbi/dashboard.pbix


---

## Implemented SSIS Packages

### Dimension Packages

- pkg_dim_customer.dtsx
- pkg_dim_equipment.dtsx
- pkg_dim_terminal.dtsx
- pkg_dim_shift.dtsx
- pkg_dim_date.dtsx


### Fact Packages

- pkg_fact_vessel_call.dtsx
- pkg_fact_container_movement.dtsx


---

## Data Quality Approach

Validation rules are applied in staging.

Examples:

- Null critical fields
- Invalid dates
- Negative durations
- Business rule violations

Invalid records are logged into:

error_table


---

## SCD Implementation

Implemented on:

dim_customer

Type:

SCD Type 2

Tracked attributes:

- customer_tier
- credit_limit

Logic:

- Detect changes
- Expire current row
- Insert new version


---

## Assumptions

1. Source Excel files are trusted.
2. Business keys are unique.
3. Excel dates are serial-based.
4. Unknown dimension values are mapped to -1.


---

## Power BI Dashboards

Included:

1. Operations Overview
2. Gate Performance Dashboard
3. Customer Vessel Performance Dashboard



---

## DAX Measures

All DAX measures are documented in:

part2_powerbi/dax_measures.md


---

## Screenshots Included

Part 1:
- Control flow
- Data flow
- SCD flow
- SQL output samples

Part 2:
- Dashboard pages
- Data model


---

## Written Questions Summary

### Why staging layer?

To preserve raw data and isolate transformations.


### Why SCD Type 2?

To preserve customer history over time.


### Why surrogate keys?

To improve performance and support historical versioning.


### Why error logging?

To improve auditing and troubleshooting.


---

## Final Notes

Database backups are intentionally excluded as requested.

All required SQL scripts and ETL packages are included.
