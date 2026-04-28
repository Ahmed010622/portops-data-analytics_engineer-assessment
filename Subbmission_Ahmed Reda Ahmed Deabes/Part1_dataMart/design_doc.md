# PortOps DataMart Design Document

## 1. Architecture Overview

The solution follows a layered data warehouse architecture:

Source Layer (Excel Files)
↓
Staging Layer (PortOps_Staging)
↓
Data Mart Layer (PortOps_Mart)
↓
Reporting Layer (Power BI)

### Source Layer
Raw operational Excel files:
- Customers
- Equipment
- Vessel Calls
- Container Movements
- Gate Transactions
- Shift Data
- Terminal Data

### Staging Layer
Purpose:
- Raw landing area
- Preserve source structure
- Initial validation
- Metadata tracking

Characteristics:
- Minimal transformations
- Raw datatypes mostly stored as text
- Validation columns included

Metadata columns:
- load_batch_id
- load_timestamp
- source_file
- is_valid
- validation_message

### Mart Layer
Purpose:
- Analytical model
- Star schema design
- Optimized for reporting

Contains:
Dimension tables:
- dim_customer
- dim_terminal
- dim_equipment
- dim_shift
- dim_date

Fact tables:
- fact_vessel_call
- fact_container_movement


---

## 2. Star Schema Design

### Dimension Tables

#### dim_customer
Type: Slowly Changing Dimension Type 2

Business key:
customer_id

Surrogate key:
customer_sk

Tracked attributes:
- customer_tier
- credit_limit

Reason:
Customer business attributes can change over time.

Historical tracking:
- effective_from
- effective_to
- is_current
- change_reason


#### dim_terminal
Purpose:
Terminal reference data


#### dim_equipment
Purpose:
Equipment operational analysis


#### dim_shift
Purpose:
Time segmentation for operations


#### dim_date
Purpose:
Calendar intelligence and time analysis


---

## 3. SCD Strategy

### Why SCD Type 2 for Customer?

Customer tier and credit limit are historical business attributes.

Example:
Customer A:
2024 → Gold
2025 → Platinum

Business users need both states for trend analysis.

Implementation:
1. Detect changes using Lookup
2. Conditional Split for changed records
3. Expire old version
4. Insert new version

Change detection attributes:
- customer_tier
- credit_limit


---

## 4. Data Quality Rules

### Customer

Rule:
customer_id must exist

Action:
Invalid rows flagged


Rule:
credit_limit must be numeric

Action:
Invalid rows rejected


### Vessel Calls

Rule:
ATA cannot be NULL

Action:
Mark invalid


Rule:
ATD must be >= ATA

Action:
Mark invalid


### Container Movements

Rule:
move_end_time >= move_start_time

Action:
Mark invalid


Rule:
move date must exist

Action:
Mark invalid


---

## 5. Error Handling Strategy

All invalid records are written into:

error_table

Captured attributes:
- batch_id
- package_name
- source_table
- error_description
- raw_row

Purpose:
- Auditability
- Debugging
- Data quality tracking


---

## 6. Date Handling

Source system uses Excel serial dates.

Transformation logic:
Excel serial → SQL date/datetime

Formula:
DATEADD(day, serial_number - 2, '1900-01-01')

Reason:
Excel stores dates as numeric serials.


---

## 7. Surrogate Key Strategy

All dimensions use surrogate keys.

Reason:
- Performance
- Historical tracking
- Decoupling source keys


Unknown members:
-1

Used when:
Dimension lookup fails.


---

## 8. Fact Table Design

### fact_vessel_call

Grain:
One row per vessel call

Measures:
- berth_delay_hours
- stay_hours
- total_moves_planned
- total_moves_actual
- moves_variance


### fact_container_movement

Grain:
One row per container movement

Measures:
- crane_cycle_seconds


---

## 9. ETL Flow Design

Step 1:
Extract from Excel

Step 2:
Load into staging

Step 3:
Validate staging

Step 4:
Load dimensions

Step 5:
Load facts

Step 6:
Power BI reporting


---

## 10. Trade-offs

Decision:
Use staging raw datatypes as NVARCHAR

Advantage:
Flexible ingestion

Trade-off:
Transformation complexity


Decision:
Use SCD2 only for customer

Advantage:
Preserve business history

Trade-off:
Larger dimension table


Decision:
Unknown surrogate key = -1

Advantage:
Prevent load failure

Trade-off:
Requires cleanup analysis


---

## 11. Performance Considerations

Implemented:
- Lookup cache
- Set-based SQL loads
- Indexed surrogate keys

Future improvements:
- Incremental loads
- Partitioning
- CDC


---

## 12. Assumptions

- Excel files are the source of truth
- Business keys are stable
- Historical customer changes are required
- Date serial format follows Excel standard