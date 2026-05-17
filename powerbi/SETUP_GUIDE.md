# Connecting Power BI Desktop to ClickHouse Cloud

## Prerequisites
- Power BI Desktop installed (free: https://powerbi.microsoft.com/desktop/)
- dbt models run successfully (`dbt run --profiles-dir .` in the `dbt/` directory)
- Your ClickHouse Cloud credentials from `.env`

---

## Method 1: ODBC Driver (Recommended — full feature support, works with Cloud)

### Install ClickHouse ODBC Driver

1. Download from: https://github.com/ClickHouse/clickhouse-odbc/releases
   - Choose: `clickhouse-odbc-*-win64.msi` (64-bit Windows)
2. Run the installer, accept defaults

### Configure ODBC Data Source

1. Open **ODBC Data Sources (64-bit)** (search Windows Start menu)
2. Click **System DSN → Add**
3. Select **ClickHouse ODBC Driver (Unicode)**
4. Fill in your ClickHouse Cloud details:
   - **Name:** `ClickHouse_UA`
   - **Host:** `your_cluster.us-east-1.aws.clickhouse.cloud` (from your `.env`)
   - **Port:** `8443`
   - **Database:** `marts`
   - **User:** `default`
   - **Password:** your ClickHouse Cloud password
   - **SSLMode:** `require` ← important for Cloud, must enable TLS
5. Click **Test** → should show "Connection successful"
6. Click **OK**

### Connect Power BI

1. Power BI Desktop → **Get Data → ODBC**
2. Select `ClickHouse_UA` from the dropdown
3. Browse to the `marts` database
4. Select tables to import:
   - `mart_creative_burnout`
   - `mart_unit_economics`
   - `mart_cohort_analysis`
   - `mart_campaign_performance`
   - `mart_skan_attribution`
5. Click **Load** (or **Transform Data** to preview first)

---

## Method 2: HTTP/Web Connector (No driver install — quick test)

Power BI can query ClickHouse Cloud via the **Web connector** using its HTTPS API.

1. Open Power BI Desktop → **Get Data → Web**
2. Use **Advanced** mode and set:
   - **URL:** `https://YOUR_HOST.clickhouse.cloud:8443/`
   - **HTTP request header parameters:** add `X-ClickHouse-User: default`
3. Or use a Power Query M function (paste into **Advanced Editor**):

```m
let
    Host = "YOUR_HOST.clickhouse.cloud",
    Password = "YOUR_PASSWORD",
    Query = "SELECT * FROM marts.mart_creative_burnout FORMAT JSONEachRow",
    Url = "https://" & Host & ":8443/?query=" & Uri.EscapeDataString(Query),
    Headers = [
        #"X-ClickHouse-User" = "default",
        #"X-ClickHouse-Key"  = Password
    ],
    Response = Web.Contents(Url, [Headers = Headers]),
    Lines    = Lines.FromBinary(Response),
    Json     = List.Transform(Lines, each Json.Document(_)),
    Result   = Table.FromList(Json, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
in
    Result
```

Replace `YOUR_HOST` and `YOUR_PASSWORD` with values from your `.env`.

---

## Recommended Dashboard Structure

### Page 1 — Creative Burnout ★ (Headline)
| Visual | Fields |
|---|---|
| Line chart: CTR over time | x=day_of_life, y=ctr_7d_avg, color=format_group |
| Scatter: Burnout score by creative | x=burnout_day_of_life, y=wasted_spend_usd, size=cumulative_spend_usd |
| Table: Top burnt creatives | creative_name, lifecycle_stage, burnout_score, wasted_spend_usd |
| Card: Total wasted spend | SUM(wasted_spend_usd) |
| Slicer: Network, Format | filters |

### Page 2 — Unit Economics
| Visual | Fields |
|---|---|
| Bar: CAC by network | network, cac_usd |
| Line: LTV curve (D7/D14/D30) | network, ltv_d7/d14/d30 |
| Matrix: ROAS by campaign | campaign_name, roas_d7, roas_d14, roas_d30 |
| Bar: Payback period distribution | payback_period_bucket, count |

### Page 3 — Cohort Analysis
| Visual | Fields |
|---|---|
| Matrix heatmap: ARPU by cohort week | install_week (rows), cohort day (columns), arpu_d7 (values) |
| Line: ROAS D7/D14/D30 trend | install_week, roas_d7, roas_d14, roas_d30 |
| Bar: Installs by network over time | install_week, total_installs, color=network |

### Page 4 — SKAN Attribution
| Visual | Fields |
|---|---|
| Donut: CV bucket distribution | cv_bucket (legend), sum(postbacks) |
| Bar: Privacy threshold impact | network, fine_cv_postbacks, low_threshold_postbacks, medium_threshold_postbacks |
| Line: SKAN coverage rate | install_date, skan_coverage_rate |
| KPI cards | avg_conversion_value, monetisation_rate, skan_roas |

---

## DirectQuery vs Import Mode

For this portfolio project, use **Import mode** (loads data into Power BI memory):
- Faster for dashboards
- No live ClickHouse connection needed for sharing

For a production setup, use **DirectQuery** so the dashboard always shows fresh data.
