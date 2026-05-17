# ClickHouse + dbt-clickhouse: Known Issues & Fixes

This document captures every compatibility issue encountered building this project, with root causes and fixes. All patterns here apply to **dbt-clickhouse 1.10 + ClickHouse Cloud**.

---

## 1. `USING` in JOINs pollutes column names with table alias prefix

**Symptom**
```
DB::Exception: Identifier 'ci.campaign_id' cannot be resolved from subquery with name ci.
Maybe you meant: ['s.campaign_id'].
```

**Root cause**  
When you write `JOIN t USING (col)` inside a CTE, ClickHouse sometimes materialises the column with the source table's alias prefix — so the physical column name becomes `s.campaign_id` instead of `campaign_id`. Downstream JOINs on `ci.campaign_id` then fail because that bare name doesn't exist.

**Fix**  
Replace every `USING (col)` with an explicit `ON` condition:
```sql
-- ❌ Wrong
inner join campaigns camp using (campaign_id)

-- ✓ Correct
inner join campaigns camp on camp.campaign_id = s.campaign_id
```

---

## 2. Table-qualified columns without `AS` alias store the prefix in the column name

**Symptom**
```
DB::Exception: Unknown expression identifier `creative_id` in scope ...
Maybe you meant: ['creative_name'].
```

**Root cause**  
When dbt-clickhouse materialises a model as a table via `CREATE TABLE AS SELECT`, ClickHouse preserves the table alias prefix in the column name if no explicit alias is given. So `SELECT s.creative_id FROM t AS s` creates a physical column literally named `s.creative_id`, not `creative_id`.

**Fix**  
Add an explicit `AS` alias to **every** table-qualified column reference:
```sql
-- ❌ Wrong — stored as "s.creative_id" in the physical table
select s.creative_id, c.creative_name, camp.objective

-- ✓ Correct — stored as "creative_id", "creative_name", "objective"
select
    s.creative_id    as creative_id,
    c.creative_name  as creative_name,
    camp.objective   as objective
```

This applies to all three layers — staging, intermediate, and marts.

---

## 3. Positional `GROUP BY` is unreliable in CTE chains

**Symptom**  
Incorrect grouping silently, or `Unknown identifier` errors, when CTEs are chained.

**Root cause**  
ClickHouse CTEs are **inline macro substitutions**, not named subqueries. When CTE B references CTE A, ClickHouse substitutes A's SQL inline before compiling B. Positional `GROUP BY 1, 2, 3` refers to positions in the expanded SQL, which may not match the intended columns.

**Fix**  
Always use named GROUP BY:
```sql
-- ❌ Wrong
group by 1, 2, 3, 4, 5, 6

-- ✓ Correct
group by install_date, campaign_id, creative_id, network, country, skan_version
```

---

## 4. Multi-level CTE chains lose column resolution in JOINs

**Symptom**
```
DB::Exception: Unknown expression identifier `creative_id` in scope creative_peaks AS p.
```

**Root cause**  
ClickHouse CTEs are not named subqueries — they are text substitutions. A chain like `CTE_A → CTE_B (joins CTE_A) → CTE_C (joins CTE_B)` causes ClickHouse to substitute and expand the chain, losing the ability to resolve column names from the intermediate CTE.

**Fix**  
Break the chain by materialising intermediate CTEs as **separate dbt models** (real ClickHouse tables):

```
-- ❌ Wrong: burnout_mart CTE references creative_peaks CTE references daily CTE
-- → ClickHouse can't resolve creative_id in creative_peaks scope

-- ✓ Correct: extract creative_peaks and burnout_events as real tables
int_creative_peaks.sql      -- materialized = 'table'
int_burnout_events.sql      -- materialized = 'table'
mart_creative_burnout.sql   -- JOINs the two real tables, no multi-level CTE chain
```

---

## 5. Window functions in CTEs that are then JOINed

**Symptom**
```
DB::Exception: Unknown expression identifier `campaign_id` in scope with_rolling.
```

**Root cause**  
ClickHouse cannot resolve column names when a CTE containing a window function is JOINed with another CTE — the inline expansion breaks column scope.

**Fix**  
Use a flat single `SELECT` with table-qualified references in window functions. No CTEs needed:
```sql
-- ✓ Correct: flat query, all window functions reference the source table alias
select
    s.creative_id    as creative_id,
    avg(s.ctr) over (partition by s.creative_id order by s.stat_date ...) as ctr_7d_avg
from stg_ad_stats s
inner join stg_creatives c on c.creative_id = s.creative_id
```

---

## 6. `avg()` over all-NULL window returns `nan`, not `NULL`

**Symptom**  
Power BI fails to parse a numeric column, reporting a format error. ClickHouse exports `nan` or `inf` as literal strings in CSV, which BI tools reject.

**Root cause**  
ClickHouse aggregate functions (`avg`, `sum`) over an empty or all-NULL window return `nan` instead of `NULL`. This is most common in rolling window columns during the first N days of data when there are no preceding rows.

**Fix**  
Wrap ratio/division columns with `isNaN` and `isInfinite` guards:
```sql
if(
    isNaN(blended_cpi_usd / nullif(avg(blended_cpi_usd) over (...), 0))
    or isInfinite(blended_cpi_usd / nullif(avg(blended_cpi_usd) over (...), 0)),
    null,
    round(blended_cpi_usd / nullif(avg(blended_cpi_usd) over (...), 0), 4)
) as cpi_trend_ratio
```

---

## 7. Incremental model unique_key columns must have explicit `AS` aliases

**Symptom**
```
DB::Exception: Missing columns: 'creative_id' while processing: 'creative_id, stat_date'.
Available columns: 'd.creative_id', 'stat_date', ...
```

**Root cause**  
dbt's `delete+insert` incremental strategy queries the result set for the `unique_key` columns by name. If the SELECT produces `d.creative_id` (no alias), the column is named `d.creative_id` in the result, and dbt can't find `creative_id`.

**Fix**  
This is a specific case of issue #2. Ensure every column in the final SELECT of an incremental model has an explicit `AS` alias, especially the `unique_key` columns:
```sql
-- mart_creative_burnout.sql (unique_key = ['creative_id', 'stat_date'])
select
    d.stat_date    as stat_date,    -- ✓ explicit alias
    d.creative_id  as creative_id,  -- ✓ explicit alias
    ...
```

---

## 8. Python version incompatibility with dbt

**Symptom**
```
mashumaro.exceptions.UnserializableField: ...
```
or any cryptic import error during `dbt deps` or `dbt run`.

**Root cause**  
dbt-core (as of 1.x) does not support Python 3.13+. Python 3.14 (pre-release) breaks dbt's serialization layer.

**Fix**  
Use Python 3.12:
```bash
py -3.12 -m venv .venv
.venv\Scripts\activate
pip install dbt-core dbt-clickhouse
```

---

## 9. ClickHouse Cloud connection — correct settings

ClickHouse Cloud does **not** use the default native protocol port (9000). Always connect via HTTPS:

| Setting | Value |
|---|---|
| Host | `your-service.us-east-1.aws.clickhouse.cloud` |
| Port | `8443` (HTTPS, not 9000 or 8123) |
| Protocol | HTTPS / secure |
| User | `default` |

**dbt profiles.yml:**
```yaml
ios_ua_analytics:
  target: dev
  outputs:
    dev:
      type: clickhouse
      host: "{{ env_var('CLICKHOUSE_HOST') }}"
      port: 8443
      secure: true
      user: default
      password: "{{ env_var('CLICKHOUSE_PASSWORD') }}"
      schema: marts
```

**Python (urllib — no extra packages needed):**
```python
url = f"https://{host}:8443/"
req = urllib.request.Request(url, data=sql.encode(), method="POST")
req.add_header("X-ClickHouse-User", user)
req.add_header("X-ClickHouse-Key", password)
```

---

## 10. ClickHouse Cloud password setup (Google SSO)

If you signed up via Google SSO, you may not have received a password prompt. To set one manually, run this in the ClickHouse Cloud SQL console:

```sql
ALTER USER default IDENTIFIED BY 'your_password_here';
```

Then retrieve your host from the **Connect** panel (not the internal cluster hostname — use the public one ending in `.clickhouse.cloud`).

---

## Summary table

| # | Error pattern | Root cause | Fix |
|---|---|---|---|
| 1 | `ci.col cannot be resolved` | `USING` pollutes column names | Replace with `ON` |
| 2 | `Unknown identifier 'col'` | Missing `AS` alias on `t.col` | Add explicit `AS col` everywhere |
| 3 | Silent wrong grouping | Positional `GROUP BY` in CTE chains | Use named GROUP BY |
| 4 | `identifier 'col' in scope CTE_name` | Multi-level CTE chain collapse | Extract to separate materialized models |
| 5 | `identifier 'col' in scope with_rolling` | Window fn + JOIN in same CTE | Flat single SELECT with table aliases |
| 6 | Power BI format error on numeric col | `avg()` of NULL window → `nan` | Wrap with `isNaN` / `isInfinite` guard |
| 7 | `Missing columns: 'creative_id'` | Incremental key column has no AS alias | Add `AS col` to unique_key columns |
| 8 | dbt deps / run crash | Python 3.13+ incompatible | Use Python 3.12 |
| 9 | Connection refused | Wrong port (8123/9000 vs 8443) | Use port 8443, `secure: true` |
| 10 | No password (Google SSO) | SSO skips password setup | `ALTER USER default IDENTIFIED BY '...'` |
