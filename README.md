# iOS UA Analytics — End-to-End Data Platform

> A production-grade iOS User Acquisition analytics pipeline built as a portfolio project, covering the full data lifecycle: ingestion → warehouse → transformation → orchestration → BI.

---

## The Insight: Creative Burnout Curve

**Every ad creative has a lifecycle.** CTR rises in the first few days as the algorithm finds the right audience, peaks, then decays as the audience saturates. Running creatives past this burnout threshold wastes budget — our model shows that installs acquired in the post-burnout phase cost **2–3x more** than during the peak window.

This project builds an automated burnout detection system that:
1. Calculates the burnout threshold for each creative daily
2. Flags creatives in each lifecycle stage (`warming_up` → `peak` → `declining` → `burnt`)
3. Quantifies the wasted spend after burnout
4. Suggests an optimal rotation schedule by creative format

**Key finding:** Video creatives (15s/30s) burn out ~2x faster than static images but generate 30% lower CPI during their peak window. The optimal strategy is to rotate videos every 10–12 days while static images can run 20–25 days before efficiency degrades.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         DATA SOURCES                            │
│  Synthetic iOS UA data (SKAN 4.0 format)                        │
│  Simulates: AppsFlyer / AppMetrica MMP export                   │
└────────────────────┬────────────────────────────────────────────┘
                     │ Python (generate_data.py)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                    INGESTION LAYER                               │
│  load_to_clickhouse.py                                          │
│  urllib HTTP POST | CSVWithNames format | idempotent TRUNCATE   │
└────────────────────┬────────────────────────────────────────────┘
                     │ HTTPS API (port 8443)
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│           CLICKHOUSE CLOUD (us-east-1, free tier)               │
│                                                                 │
│  raw.*               Landing zone — immutable raw tables        │
│  marts_staging.*     Cleaned & typed (dbt views)                │
│  marts_intermediate.*  Business logic & joins (dbt tables)      │
│  marts_marts.*       Analytics-ready tables for BI (dbt tables) │
└────────────────────┬────────────────────────────────────────────┘
                     │ dbt-core + dbt-clickhouse 1.10
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│                  TRANSFORMATION (dbt)                           │
│                                                                 │
│  Staging:       stg_campaigns, stg_creatives, stg_ad_stats,    │
│                 stg_skan_postbacks, stg_iap_events              │
│  Intermediate:  int_creative_daily_metrics, int_creative_peaks, │
│                 int_burnout_events, int_cohort_installs,        │
│                 int_cohort_revenue, int_skan_cv_mapping         │
│  Marts:         mart_creative_burnout ★ (incremental)           │
│                 mart_unit_economics, mart_cohort_analysis        │
│                 mart_campaign_performance, mart_skan_attribution │
└────────────────────┬────────────────────────────────────────────┘
                     │
              ┌──────┴──────┐
              ▼             ▼
┌─────────────────┐   ┌──────────────────────────────────────────┐
│  ORCHESTRATION  │   │              BI / VISUALISATION           │
│  Airflow 2.9    │   │  Power BI Desktop                        │
│  daily_ua_dag   │   │  Official ClickHouse connector           │
│  weekly_cohort  │   │  4 pages: Burnout | Unit Econ |          │
│  SLA + retries  │   │  Cohorts | SKAN Attribution              │
└─────────────────┘   └──────────────────────────────────────────┘
```

---

## Stack

| Layer | Technology | Notes |
|---|---|---|
| Warehouse | ClickHouse Cloud (free tier) | Columnar, blazing-fast aggregations, HTTPS API on port 8443 |
| Transformation | dbt-core 1.11 + dbt-clickhouse 1.10 | 3-layer architecture, incremental models, 25 tests |
| Orchestration | Apache Airflow 2.9 | DAG files in `airflow/dags/` — see Airflow section |
| Ingestion | Python 3.12 + urllib | Direct CSV upload via ClickHouse HTTP API, no extra dependencies |
| Data generation | Python (pandas, numpy, faker) | Realistic SKAN 4.0 format with embedded burnout patterns |
| BI | Power BI Desktop | Official ClickHouse connector (`.mez`) |
| Version control | Git + GitHub | CI via GitHub Actions (`dbt test` on every push) |

---

## dbt Model DAG

```
RAW (ClickHouse)          STAGING (views)              INTERMEDIATE (tables)             MARTS (tables)
─────────────────         ──────────────────           ──────────────────────────        ──────────────────────────────
campaigns          ──►  stg_campaigns   ──┐
creatives          ──►  stg_creatives   ──┼──►  int_creative_daily_metrics ──►  int_creative_peaks
ad_daily_stats     ──►  stg_ad_stats    ──┘           │                    └──►  int_burnout_events
                                                       │                               │
                                           ┌───────────┴───────────────────────────────┘
                                           └──────────────────────────────────────────────►  mart_creative_burnout ★

campaigns    ──►  stg_campaigns   ──┐
creatives    ──►  stg_creatives   ──┼──►  int_cohort_installs ──┐
ad_stats     ──►  stg_ad_stats    ──┘                           ├──►  mart_unit_economics
                                                                │
iap_events   ──►  stg_iap_events  ──►  int_cohort_revenue ──────┼──►  mart_cohort_analysis

ad_stats     ──►  stg_ad_stats  ──────────────────────────────────►  mart_campaign_performance
campaigns    ──►  stg_campaigns ──┘

skan_postbacks ──►  stg_skan_postbacks ──►  int_skan_cv_mapping ──►  mart_skan_attribution
```

To view the interactive version:
```bash
cd dbt
dbt docs generate
dbt docs serve   # opens http://localhost:8080
```

---

## Data Model

The simulation generates 90 days of iOS UA data across 5 networks (Meta, Google UAC, ASA, TikTok, Snap):

| Table | Rows | Description |
|---|---|---|
| `raw.campaigns` | 16 | UA campaigns |
| `raw.creatives` | 85 | Ad creatives per campaign |
| `raw.ad_daily_stats` | 2,705 | Daily impressions, clicks, spend, installs per creative |
| `raw.skan_postbacks` | 100,478 | SKAN 4.0 postbacks with conversion values |
| `raw.iap_events` | 31,181 | In-app purchase and subscription events |

**SKAN Conversion Value Schema (6-bit, subscription app):**
- CV 0 = no event / install only
- CV 1–2 = engagement (tutorial, onboarding)
- CV 3 = trial started
- CV 4–7 = low revenue tier (weekly sub)
- CV 8–15 = mid revenue tier (monthly sub)
- CV 16–63 = high revenue tier (annual sub / renewals)

---

## Setup Guide

### Prerequisites

- Python **3.12** (dbt is incompatible with 3.13+)
- Git
- Power BI Desktop (Windows only, free)
- Free [ClickHouse Cloud](https://clickhouse.cloud) account

### 1. Clone the repo

```bash
git clone https://github.com/YOUR_USERNAME/ios-ua-analytics.git
cd ios-ua-analytics
```

### 2. Set up ClickHouse Cloud

1. Go to [clickhouse.cloud](https://clickhouse.cloud) → **Start for free**
2. Create a service — `Development` tier, any region
3. Click **Connect** in the console → copy the hostname and password
4. In the project root, create your credentials file:

```bash
Copy-Item .env.example .env
notepad .env
```

```env
CLICKHOUSE_HOST=your-host.us-east-1.aws.clickhouse.cloud
CLICKHOUSE_PORT=8443
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=your_password_here
```

5. In the ClickHouse Cloud SQL console, create the raw schema and tables:
```sql
CREATE DATABASE IF NOT EXISTS raw;
```
Then paste and run `docker/clickhouse/init/02_create_raw_tables.sql`.

### 3. Generate and load data

```bash
cd ingestion
pip install -r requirements.txt --break-system-packages
python generate_data.py          # ~30s — creates CSVs in ingestion/data/
python load_to_clickhouse.py     # loads all 5 tables into ClickHouse Cloud
```

Expected output:
```
Loading campaigns       → raw.campaigns          ✓  16 rows
Loading creatives       → raw.creatives          ✓  85 rows
Loading ad_daily_stats  → raw.ad_daily_stats     ✓  2,705 rows
Loading skan_postbacks  → raw.skan_postbacks     ✓  100,478 rows
Loading iap_events      → raw.iap_events         ✓  31,181 rows
```

### 4. Install dbt and run models

```bash
# Use Python 3.12 (not 3.13+)
py -3.12 -m venv .venv
.venv\Scripts\activate

pip install dbt-core dbt-clickhouse

cd dbt
dbt deps

# Set credentials (PowerShell)
$env:CLICKHOUSE_HOST     = "your-host.clickhouse.cloud"
$env:CLICKHOUSE_PASSWORD = "your_password"

dbt run        # builds all 16 models
dbt test       # runs 25 data quality tests
dbt docs generate && dbt docs serve
```

Expected: `16 of 16 OK`, `25 of 25 PASS`

### 5. Connect Power BI

See [powerbi/SETUP_GUIDE.md](powerbi/SETUP_GUIDE.md).

**Quick start:**
1. Download the official connector `.mez` from [github.com/ClickHouse/power-bi-clickhouse/releases](https://github.com/ClickHouse/power-bi-clickhouse/releases)
2. Place in `Documents\Power BI Desktop\Custom Connectors\`
3. Power BI → Options → Security → Data Extensions → Allow any extension
4. Restart Power BI → Get Data → **ClickHouse**
5. Server: `your-host.clickhouse.cloud` | Port: `8443` | Database: `marts_marts`

### 6. Airflow (orchestration)

Airflow runs on Linux. The DAG files in `airflow/dags/` demonstrate production orchestration design. To run locally on Windows, use WSL2 or deploy to any Linux VM.

---

## dbt Model Reference

### Staging (views — `marts_staging` schema)

| Model | Source | Key transformations |
|---|---|---|
| `stg_campaigns` | raw.campaigns | is_active flag |
| `stg_creatives` | raw.creatives | format_group, is_video |
| `stg_ad_stats` | raw.ad_daily_stats | CTR, CPI, CVR, CPM derived |
| `stg_skan_postbacks` | raw.skan_postbacks | CV bucket decode, privacy threshold, revenue estimate |
| `stg_iap_events` | raw.iap_events | days_since_install, product_tier |

### Intermediate (tables — `marts_intermediate` schema)

| Model | Description |
|---|---|
| `int_creative_daily_metrics` | Per-creative daily metrics + day_of_life + rolling 7d CTR + cumulative spend |
| `int_creative_peaks` | Peak CTR and peak day per creative (materialized for burnout JOIN) |
| `int_burnout_events` | First burnout date per creative (materialized for burnout JOIN) |
| `int_cohort_installs` | Installs + spend + CAC by (install_date, campaign, creative) |
| `int_cohort_revenue` | Revenue by cohort and days_since_install + LTV + ROAS |
| `int_skan_cv_mapping` | SKAN postbacks aggregated + CV distribution + privacy breakdown |

### Marts (tables — `marts_marts` schema)

| Model | Key columns | Business question answered |
|---|---|---|
| `mart_creative_burnout` ★ | burnout_score, lifecycle_stage, wasted_spend_usd | When does each creative peak and burn? |
| `mart_unit_economics` | cac_usd, ltv_d7/d14/d30, roas_d7/d14/d30, payback_period_bucket | Which campaigns pay back and when? |
| `mart_cohort_analysis` | arpu_d1/d7/d14/d30, roas_d7/d14/d30 | How do install cohorts monetise over time? |
| `mart_campaign_performance` | blended_cpi_usd, cpi_trend_ratio, saturation_flag | Which campaigns are saturating? |
| `mart_skan_attribution` | skan_coverage_rate, fine_signal_rate, privacy_loss_rate, skan_roas | How complete and reliable is our SKAN signal? |

---

## JD Coverage

| Prequel Senior Marketing Analyst requirement | Implemented in |
|---|---|
| Cohort analysis | `mart_cohort_analysis`, `int_cohort_revenue` |
| Unit economics (CAC / LTV / ROAS) | `mart_unit_economics` |
| Payback periods | `mart_unit_economics.payback_period_bucket` |
| Campaign performance reviews | `mart_campaign_performance` |
| Creative deep-dive + burnout detection | `mart_creative_burnout` ★ |
| Campaign saturation identification | `mart_campaign_performance.saturation_flag` |
| Traffic mix analysis | `int_creative_daily_metrics` (network × format split) |
| Growth opportunity identification | Burnout → rotation schedule recommendation |
| Data marts in dbt | 5 mart models, full 3-layer architecture, 25 tests |
| Automate routine tasks | Airflow DAGs with SLAs, retries, backfill |
| iOS UA + SKAN 4.0 expertise | SKAN data model, `mart_skan_attribution` |
| Advanced SQL / ClickHouse | Window functions, incremental models, isNaN guards |
| Python: pandas, numpy, automation | `generate_data.py`, `load_to_clickhouse.py` |
| dbt: modeling, incremental, testing, docs | Incremental mart, schema tests, `dbt docs` |

---

## Key Findings

1. **Creative burnout is format-dependent:** Video (15s) creatives peak at day 4–5 and cross the burnout threshold by day 12. Static images sustain efficiency up to day 22.

2. **Post-burnout CPI inflation:** Continuing to run creatives after the burnout threshold inflates CPI by 2.3× on average. ~18% of total simulated spend was wasted on burnt creatives.

3. **Optimal rotation schedule by format:**
   - `video_15s` → rotate at day 10
   - `video_30s` → rotate at day 14
   - `static_image` → rotate at day 21
   - `carousel` → rotate at day 16

4. **Apple Search Ads has the strongest SKAN signal:** 95%+ fine conversion value rate vs 70–80% for Meta/TikTok, making ASA the most reliable source for SKAN-based LTV modelling.

5. **D7 ROAS varies 3× across campaigns:** Best performer (ASA_iOS_Subscriptions) at D7 ROAS 0.42; worst (Snap_iOS_Installs) at 0.13. Annual sub products drive the fastest payback.

---

## Project Structure

```
ios-ua-analytics/
├── README.md
├── .env.example
├── .gitignore
├── .github/workflows/ci.yml           # dbt test on every push
├── docs/
│   ├── clickhouse_dbt_gotchas.md      # Known ClickHouse+dbt issues + fixes
│   └── powerbi_setup.md               # Power BI connection guide (detailed)
├── ingestion/
│   ├── generate_data.py               # Synthetic SKAN 4.0 data generator
│   ├── load_to_clickhouse.py          # ClickHouse loader (urllib HTTP POST)
│   └── requirements.txt
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── models/
│   │   ├── staging/                   # 5 view models
│   │   ├── intermediate/              # 6 table models
│   │   └── marts/                     # 5 table models (1 incremental)
│   └── tests/                         # custom data tests
├── airflow/dags/
│   ├── daily_ua_pipeline.py           # Daily orchestration DAG
│   └── weekly_cohort_refresh.py       # Weekly backfill DAG
└── powerbi/
    └── ios_ua_analytics.pbix          # Power BI report file
```

---

## Author

Andrey Blanket | andrey.blanket@gmail.com
