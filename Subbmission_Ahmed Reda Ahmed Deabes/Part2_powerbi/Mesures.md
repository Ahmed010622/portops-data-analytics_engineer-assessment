# PortOps Dashboard — DAX Measures

All 8 measures with full code and explanations.

---

## Measure 1 — Total Container Moves

**Table:** fact_container_movement

```dax
Total Container Moves = COUNTROWS(fact_container_movement)
```

**Explanation:**
Counts every row in fact_container_movement. Since the grain of this fact table is one row per container move, COUNTROWS() gives the exact total number of moves. This measure is fully additive and responds correctly to all slicers (date, customer, terminal, shift). It is used as the base measure for Measures 6 and 7.

---

## Measure 2 — Avg Crane Cycle Seconds

**Table:** fact_container_movement

```dax
Avg Crane Cycle Seconds =
DIVIDE(
    SUMX(
        FILTER(fact_container_movement,
               fact_container_movement[crane_cycle_seconds] > 0),
        fact_container_movement[crane_cycle_seconds]
    ),
    COUNTROWS(
        FILTER(fact_container_movement,
               fact_container_movement[crane_cycle_seconds] > 0)
    ),
    0
)
```

**Explanation:**
Calculates the average crane cycle time in seconds, excluding NULL and zero values (which indicate missing timestamps). DIVIDE() is used instead of the division operator to return 0 rather than an error when no valid rows exist. SUMX() with FILTER() is preferred over AVERAGEX() to ensure the same filter is applied consistently to both numerator and denominator. crane_cycle_seconds was pre-computed in the ETL as DATEDIFF(SECOND, move_start_time, move_end_time).

---

## Measure 3 — Gate-Ins Count

**Table:** fact_gate_transaction

```dax
Gate-Ins Count = COUNTROWS(fact_gate_transaction)
```

**Explanation:**
Counts all gate transactions filtered by the ACTIVE relationship between fact_gate_transaction[gate_in_date_key] and dim_date[date_key]. When a date slicer is applied, Power BI uses this active relationship automatically, meaning the measure counts transactions by the date the truck entered the terminal. No CALCULATE or USERELATIONSHIP is needed here because the active relationship handles the filter propagation.

---

## Measure 4 — Gate-Outs Count

**Table:** fact_gate_transaction

```dax
Gate-Outs Count =
CALCULATE(
    COUNTROWS(fact_gate_transaction),
    USERELATIONSHIP(
        fact_gate_transaction[gate_out_date_key],
        dim_date[date_key]
    )
)
```

**Explanation:**
Counts transactions by gate-out date instead of gate-in date. Because Power BI only allows one active relationship between two tables, the relationship between gate_out_date_key and dim_date is set to INACTIVE in the model. USERELATIONSHIP() inside CALCULATE temporarily activates this relationship for the duration of this measure's evaluation, overriding the default active relationship. This allows a date slicer to filter gate-outs by exit date independently of gate-ins. Rows where gate_out_date_key = -1 (trucks still inside) are excluded from date-filtered counts naturally.

---

## Measure 5 — Avg Truck Turnaround Minutes

**Table:** fact_gate_transaction

```dax
Avg Truck Turnaround Minutes =
DIVIDE(
    SUMX(
        FILTER(fact_gate_transaction,
               fact_gate_transaction[truck_turnaround_minutes] > 0),
        fact_gate_transaction[truck_turnaround_minutes]
    ),
    COUNTROWS(
        FILTER(fact_gate_transaction,
               fact_gate_transaction[truck_turnaround_minutes] > 0)
    ),
    0
)
```

**Explanation:**
Calculates average truck turnaround time in minutes, excluding NULL values (trucks that have not exited yet) and any negative values (data quality issues). truck_turnaround_minutes was pre-computed in the ETL as DATEDIFF(SECOND, gate_in_time, gate_out_time) / 60.0. The same DIVIDE + FILTER pattern as Measure 2 is used for consistency and to handle edge cases gracefully.

---

## Measure 6 — Moves YoY %

**Table:** fact_container_movement

```dax
Moves YoY % =
VAR CurrentMoves = [Total Container Moves]
VAR PriorMoves =
    CALCULATE(
        [Total Container Moves],
        DATEADD(dim_date[full_date], -1, YEAR)
    )
RETURN
    DIVIDE(CurrentMoves - PriorMoves, PriorMoves, BLANK())
```

**Explanation:**
Calculates year-over-year percentage change in container moves. DATEADD shifts the date context back by one year to compute the prior period value. VAR/RETURN pattern is used for readability and to avoid evaluating [Total Container Moves] twice. DIVIDE returns BLANK() (not 0) when prior year has no data, which prevents misleading 100% values for customers that did not exist in the prior year. dim_date must be marked as a Date Table for DATEADD to function correctly. Format the measure as Percentage with 1 decimal place.

---

## Measure 7 — Moves 7-Day Rolling Average

**Table:** fact_container_movement

```dax
Moves 7-Day Rolling Avg =
CALCULATE(
    DIVIDE([Total Container Moves], 7),
    DATESINPERIOD(
        dim_date[full_date],
        LASTDATE(dim_date[full_date]),
        -7,
        DAY
    )
)
```

**Explanation:**
Calculates a 7-day rolling average of container moves ending on the last visible date in the current filter context. DATESINPERIOD generates a dynamic 7-day window ending at LASTDATE(dim_date[full_date]). CALCULATE applies this window as a filter override on the date table. The result is divided by 7 to produce the daily average over the window. This measure is used as the secondary line on the daily moves trend chart on Page 1 to smooth out day-of-week and operational volatility.

---

## Measure 8 — Avg Berth Delay Hours

**Table:** fact_vessel_call

```dax
Avg Berth Delay Hours =
DIVIDE(
    SUM(fact_vessel_call[berth_delay_hours]),
    COUNTROWS(
        FILTER(fact_vessel_call,
               fact_vessel_call[berth_delay_hours] <> BLANK())
    ),
    0
)
```

**Explanation:**
Calculates average berth delay in hours across all vessel calls where berth_delay_hours is not blank. berth_delay_hours was pre-computed in the ETL as (ATA - ETA) in hours — positive values indicate the vessel arrived late, negative values indicate early arrival. SUM is used in the numerator rather than SUMX because berth_delay_hours is a pre-computed physical column, not a calculated expression. COUNTROWS with FILTER excludes rows where the delay could not be computed (missing ETA or ATA).
