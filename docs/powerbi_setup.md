# Power BI → ClickHouse Cloud: Setup Guide

---

## Option A — Official ClickHouse Connector (recommended)

This is the cleanest, most professional connection method. It gives a native dialog with host/port/database fields and handles SSL automatically.

### Step 1 — Download the connector

Go to: https://github.com/ClickHouse/power-bi-clickhouse/releases

Download the latest `.mez` file (e.g. `ClickHouse.mez`).

### Step 2 — Install the connector

Create the folder if it doesn't exist, then drop the file in:

```
C:\Users\<YourName>\Documents\Power BI Desktop\Custom Connectors\ClickHouse.mez
```

### Step 3 — Allow custom connectors in Power BI

Open Power BI Desktop → **File → Options and settings → Options → Security**

Under **Data Extensions**, select:  
`(Not Recommended) Allow any extension to load without validation or warning`

Restart Power BI Desktop.

### Step 4 — Connect

**Get Data → search "ClickHouse" → ClickHouse**

Fill in:

| Field | Value |
|---|---|
| Server | `your-service.us-east-1.aws.clickhouse.cloud` |
| Port | `8443` |
| Database | `marts_marts` |
| Username | `default` |
| Password | your ClickHouse password |

Click **OK** → select the tables you want → **Load**.

---

## Option B — Web Connector (fallback, no driver needed)

If the `.mez` connector is unavailable, Power BI's built-in Web connector can query ClickHouse directly via its HTTPS API.

**Get Data → Web → Advanced**

Paste into the first URL parts box (replace table name as needed):

```
https://your-host.clickhouse.cloud:8443/?user=default&password=YOUR_PASSWORD&query=SELECT%20*%20FROM%20marts_marts.mart_creative_burnout%20FORMAT%20CSVWithNames
```

When prompted for access method, choose **Anonymous** (credentials are already in the URL).

Repeat for each mart table, substituting the table name in the URL.

> **Note:** This method embeds credentials in the URL. Suitable for local development and portfolio demos, but not for shared reports. Use Option A for team environments.

---

## Tables to import

All mart tables live in the `marts_marts` database:

| Table | Power BI page |
|---|---|
| `mart_creative_burnout` | Creative Burnout |
| `mart_campaign_performance` | Campaign Overview |
| `mart_unit_economics` | Unit Economics |
| `mart_cohort_analysis` | Cohort Analysis |
| `mart_skan_attribution` | SKAN Attribution |

---

## Column type tips

After loading, go to **Transform Data** and set these column types manually if Power BI infers them incorrectly:

| Column | Type |
|---|---|
| `stat_date`, `install_date`, `launch_date`, `burnout_date` | Date |
| `burnout_score`, `ltv_*`, `roas_*`, `cac_usd`, `cpi_*`, `ctr_*` | Decimal number |
| `is_video`, `is_post_burnout`, `is_over_budget` | True/False |
| `lifecycle_stage`, `saturation_flag`, `payback_period_bucket`, `format` | Text |

---

## Refreshing data

After running `dbt run` to update the ClickHouse tables:

- Option A (connector): click **Refresh** in Power BI — it re-queries ClickHouse live.
- Option B (web): same — each URL is re-fetched on refresh.

There is no need to re-import or re-paste URLs.
