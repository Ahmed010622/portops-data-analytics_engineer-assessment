# DAX Measures Documentation

This document contains all DAX measures used in the Power BI dashboard.

---

## 1. Total Container Moves

Table:
fact_container_movement

Purpose:
Count total container movement records.

```DAX
Total Container Moves =
COUNTROWS(fact_container_movement)
```

Used in:
- KPI cards
- Trend analysis
- Customer analysis

---

## 2. Avg Crane Cycle Seconds

Table:
fact_container_movement

Purpose:
Calculate average crane operation cycle time.

```DAX
Avg Crane Cycle Seconds =
DIVIDE(
    SUMX(
        FILTER(
            fact_container_movement,
            NOT(ISBLANK(fact_container_movement[crane_cycle_seconds]))
        ),
        fact_container_movement[crane_cycle_seconds]
    ),
    COUNTROWS(
        FILTER(
            fact_container_movement,
            NOT(ISBLANK(fact_container_movement[crane_cycle_seconds]))
        )
    )
)
```

Used in:
- Operational efficiency dashboard

---

## 3. Gate-Ins Count

Table:
fact_gate_transaction

Purpose:
Count gate-in transactions.

```DAX
Gate-Ins Count =
CALCULATE(
    COUNTROWS(fact_gate_transaction),
    fact_gate_transaction[direction] = "IN"
)
```

Used in:
- Gate operations dashboard

---

## 4. Gate-Outs Count

Table:
fact_gate_transaction

Purpose:
Count gate-out transactions.

```DAX
Gate-Outs Count =
CALCULATE(
    COUNTROWS(fact_gate_transaction),
    fact_gate_transaction[direction] = "OUT"
)
```

Used in:
- Gate operations dashboard

---

## 5. Avg Truck Turnaround Minutes

Table:
fact_gate_transaction

Purpose:
Calculate average truck turnaround time.

```DAX
Avg Truck Turnaround Minutes =
DIVIDE(
    SUMX(
        FILTER(
            fact_gate_transaction,
            NOT(ISBLANK(fact_gate_transaction[turnaround_minutes]))
        ),
        fact_gate_transaction[turnaround_minutes]
    ),
    COUNTROWS(
        FILTER(
            fact_gate_transaction,
            NOT(ISBLANK(fact_gate_transaction[turnaround_minutes]))
        )
    )
)
```

Used in:
- Truck efficiency analysis

---

## 6. Moves YoY %

Table:
fact_container_movement

Purpose:
Calculate year-over-year movement growth.

```DAX
Moves YoY % =
VAR CurrentYear =
    [Total Container Moves]

VAR PreviousYear =
    CALCULATE(
        [Total Container Moves],
        DATEADD(dim_date[full_date], -1, YEAR)
    )

RETURN
DIVIDE(
    CurrentYear - PreviousYear,
    PreviousYear
)
```

Used in:
- Customer YoY comparison

---

## 7. Moves 7-Day Rolling Avg

Table:
fact_container_movement

Purpose:
Calculate rolling 7-day average.

```DAX
Moves 7-Day Rolling Avg =
CALCULATE(
    [Total Container Moves],
    DATESINPERIOD(
        dim_date[full_date],
        MAX(dim_date[full_date]),
        -7,
        DAY
    )
) / 7
```

Used in:
- Trend smoothing

---

## 8. Avg Berth Delay Hours

Table:
fact_vessel_call

Purpose:
Calculate average berth delay.

```DAX
Avg Berth Delay Hours =
DIVIDE(
    SUM(fact_vessel_call[berth_delay_hours]),
    COUNTROWS(
        FILTER(
            fact_vessel_call,
            NOT(ISBLANK(fact_vessel_call[berth_delay_hours]))
        )
    )
)
```

Used in:
- Vessel performance dashboard

---

## Notes

All measures are optimized for:
- Dashboard KPIs
- Trend analysis
- Operational performance reporting
- Customer analytics