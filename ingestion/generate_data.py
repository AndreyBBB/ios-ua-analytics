"""
generate_data.py
────────────────
Generates realistic synthetic iOS UA data in AppsFlyer / SKAN format.
Outputs CSV files to the ingestion/data/ directory.

Key realism features:
  - Creative burnout curve: CTR follows a peak-and-decay model
  - SKAN 4.0 postbacks with conversion value → revenue mapping
  - Seasonal spend patterns (weekday/weekend variance)
  - Network-specific CPI and CTR baselines
  - Privacy threshold simulation for SKAN 4

Usage:
  pip install pandas numpy faker
  python ingestion/generate_data.py

Output files (in ingestion/data/):
  campaigns.csv, creatives.csv, ad_daily_stats.csv,
  skan_postbacks.csv, iap_events.csv
"""

import math
import random
import uuid
from datetime import date, timedelta
from pathlib import Path

import numpy as np
import pandas as pd

# ─── Configuration ────────────────────────────────────────────────────────────
SEED = 42
random.seed(SEED)
np.random.seed(SEED)

OUTPUT_DIR = Path(__file__).parent / "data"
OUTPUT_DIR.mkdir(exist_ok=True)

# Simulation window: 90 days of UA activity
SIM_START = date(2024, 10, 1)
SIM_END   = date(2024, 12, 31)
SIM_DAYS  = (SIM_END - SIM_START).days + 1

DATES = [SIM_START + timedelta(days=i) for i in range(SIM_DAYS)]

# ─── Network Profiles (realistic iOS UA benchmarks) ───────────────────────────
NETWORKS = {
    "Meta":               {"cpm_usd": 12.0, "base_ctr": 0.012, "cpi_usd": 3.2,  "budget_share": 0.38},
    "Google_UAC":         {"cpm_usd": 9.5,  "base_ctr": 0.009, "cpi_usd": 2.8,  "budget_share": 0.25},
    "Apple_Search_Ads":   {"cpm_usd": 18.0, "base_ctr": 0.025, "cpi_usd": 1.9,  "budget_share": 0.20},
    "TikTok":             {"cpm_usd": 8.0,  "base_ctr": 0.018, "cpi_usd": 3.8,  "budget_share": 0.10},
    "Snap":               {"cpm_usd": 7.5,  "base_ctr": 0.008, "cpi_usd": 4.5,  "budget_share": 0.07},
}

COUNTRIES = ["US", "GB", "AU", "CA", "DE", "FR"]
COUNTRY_CPI_MULT = {"US": 1.0, "GB": 0.85, "AU": 0.80, "CA": 0.78, "DE": 0.70, "FR": 0.65}

# ─── Creative Format Burnout Profiles ─────────────────────────────────────────
# Each format has a characteristic burnout speed.
# CTR(day) = base_ctr × peak_mult × exp(-decay × max(0, day - peak_day))
FORMAT_PROFILES = {
    "video_15s": {"peak_day": 4,  "peak_mult": 1.8, "decay": 0.10, "base_ctr_mult": 1.3},
    "video_30s": {"peak_day": 6,  "peak_mult": 1.6, "decay": 0.07, "base_ctr_mult": 1.2},
    "static_image": {"peak_day": 2, "peak_mult": 1.3, "decay": 0.05, "base_ctr_mult": 0.9},
    "carousel":  {"peak_day": 3,  "peak_mult": 1.5, "decay": 0.08, "base_ctr_mult": 1.1},
}

# ─── SKAN Conversion Value → Revenue Mapping (industry standard schema) ────────
# CV 0-63 maps to revenue buckets. We use a simplified 6-bit schema.
# Bits 0-2 = event tier, bits 3-5 = revenue bucket
CV_TO_REVENUE = {
    0:  0.0,   # no event
    1:  0.0,   # app open only
    2:  0.99,  # tutorial complete
    3:  2.99,  # trial started
    4:  9.99,  # weekly sub purchased
    5:  9.99,
    6:  14.99, # weekly sub D2
    7:  14.99,
    8:  29.99, # monthly sub
    9:  29.99,
    10: 29.99,
    11: 49.99, # monthly sub renew
    12: 49.99,
    13: 79.99, # annual sub
    14: 79.99,
    15: 99.99, # annual sub renew
}
# CVs 16-63 also carry revenue, interpolated
for cv in range(16, 64):
    CV_TO_REVENUE[cv] = 99.99 + (cv - 15) * 3.0

# ─── IAP Product Definitions ──────────────────────────────────────────────────
IAP_PRODUCTS = {
    "weekly_sub":   {"price": 9.99,  "renew_rate": 0.55, "period_days": 7},
    "monthly_sub":  {"price": 29.99, "renew_rate": 0.70, "period_days": 30},
    "annual_sub":   {"price": 79.99, "renew_rate": 0.85, "period_days": 365},
    "lifetime":     {"price": 199.99,"renew_rate": 0.0,  "period_days": None},
}

# ─────────────────────────────────────────────────────────────────────────────

def sim_dates(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


def ctr_curve(day_of_life: int, network: str, fmt: str, base_ctr: float) -> float:
    """
    Return the CTR for a creative on a given day of its life.
    day_of_life=0 means the day the creative launched.
    Encodes the burnout curve: ramp up to peak, then exponential decay.
    """
    p = FORMAT_PROFILES[fmt]
    # Ramp-up phase: linear increase to peak_day
    if day_of_life <= p["peak_day"]:
        mult = 1.0 + (p["peak_mult"] - 1.0) * (day_of_life / max(p["peak_day"], 1))
    else:
        # Decay phase: exponential decay from peak
        days_past_peak = day_of_life - p["peak_day"]
        mult = p["peak_mult"] * math.exp(-p["decay"] * days_past_peak)

    raw_ctr = base_ctr * p["base_ctr_mult"] * mult
    # Add realistic daily noise (±15%)
    noise = np.random.normal(1.0, 0.08)
    return max(0.001, raw_ctr * noise)


def weekend_spend_mult(d: date) -> float:
    """iOS UA typically spends more on weekdays; slight dip on weekends."""
    return 0.85 if d.weekday() >= 5 else 1.05


# ─── 1. Generate Campaigns ────────────────────────────────────────────────────
def generate_campaigns() -> pd.DataFrame:
    print("Generating campaigns...")
    rows = []
    campaign_id = 1

    # Create 2-4 campaigns per network, staggered start dates
    for network, props in NETWORKS.items():
        n_campaigns = random.randint(2, 4)
        for i in range(n_campaigns):
            start_offset = random.randint(0, 20)
            start = SIM_START + timedelta(days=start_offset)
            # Some campaigns end mid-simulation (budget exhausted / test ended)
            has_end = random.random() < 0.3
            end = start + timedelta(days=random.randint(30, 60)) if has_end else None

            rows.append({
                "campaign_id":   f"cmp_{campaign_id:04d}",
                "campaign_name": f"{network}_iOS_{['Subscriptions','Installs','ROAS'][i % 3]}_v{i+1}",
                "network":       network,
                "objective":     "app_purchases" if i % 2 == 0 else "app_installs",
                "country":       random.choice(COUNTRIES),
                "daily_budget":  round(props["budget_share"] * random.uniform(500, 2000), 2),
                "start_date":    start.isoformat(),
                "end_date":      end.isoformat() if end else None,
            })
            campaign_id += 1

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT_DIR / "campaigns.csv", index=False)
    print(f"  → {len(df)} campaigns")
    return df


# ─── 2. Generate Creatives ────────────────────────────────────────────────────
def generate_creatives(campaigns: pd.DataFrame) -> pd.DataFrame:
    print("Generating creatives...")
    rows = []
    creative_id = 1
    formats = list(FORMAT_PROFILES.keys())

    for _, camp in campaigns.iterrows():
        # 3-8 creatives per campaign; video-heavy for Meta/TikTok
        n_creatives = random.randint(3, 8)
        camp_start = date.fromisoformat(camp["start_date"])

        for j in range(n_creatives):
            # Creatives launch in waves: some at campaign start, some mid-campaign
            creative_launch = camp_start + timedelta(days=random.randint(0, 15))
            if creative_launch > SIM_END:
                creative_launch = camp_start

            # Network bias toward certain formats
            if camp["network"] in ("Meta", "TikTok", "Snap"):
                fmt = random.choices(formats, weights=[0.5, 0.3, 0.1, 0.1])[0]
            elif camp["network"] == "Apple_Search_Ads":
                fmt = random.choices(formats, weights=[0.2, 0.1, 0.6, 0.1])[0]
            else:
                fmt = random.choice(formats)

            size_map = {
                "video_15s": "9x16", "video_30s": "9x16",
                "static_image": "1x1", "carousel": "4x5"
            }

            rows.append({
                "creative_id":   f"cre_{creative_id:05d}",
                "campaign_id":   camp["campaign_id"],
                "creative_name": f"{camp['network']}_{fmt}_v{j+1}",
                "format":        fmt,
                "size":          size_map[fmt],
                "launch_date":   creative_launch.isoformat(),
            })
            creative_id += 1

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT_DIR / "creatives.csv", index=False)
    print(f"  → {len(df)} creatives")
    return df


# ─── 3. Generate Ad Daily Stats ───────────────────────────────────────────────
def generate_ad_daily_stats(
    campaigns: pd.DataFrame,
    creatives: pd.DataFrame
) -> pd.DataFrame:
    print("Generating ad daily stats (this takes a moment)...")
    rows = []

    camp_map = campaigns.set_index("campaign_id").to_dict("index")

    for _, cre in creatives.iterrows():
        cid   = cre["campaign_id"]
        camp  = camp_map[cid]
        net   = camp["network"]
        net_props = NETWORKS[net]
        fmt   = cre["format"]
        launch = date.fromisoformat(cre["launch_date"])
        country = camp["country"]

        camp_end = (
            date.fromisoformat(str(camp["end_date"]))
            if camp["end_date"] and str(camp["end_date"]) != "nan" else SIM_END
        )

        # Creative active for min(90, campaign_duration) days
        creative_lifespan = random.randint(14, 60)
        creative_end = min(launch + timedelta(days=creative_lifespan), camp_end, SIM_END)

        if launch > creative_end:
            continue

        # Daily budget split across active creatives (simplified: equal split)
        n_active_creatives = 4  # approximate denominator
        daily_creative_budget = camp["daily_budget"] / n_active_creatives

        for d in sim_dates(launch, creative_end):
            day_of_life = (d - launch).days

            # Spend with weekday seasonality
            spend = daily_creative_budget * weekend_spend_mult(d) * np.random.normal(1.0, 0.12)
            spend = max(10.0, spend)

            # Impressions from CPM
            cpm = net_props["cpm_usd"] * np.random.normal(1.0, 0.10)
            impressions = int((spend / max(cpm, 0.1)) * 1000)

            # CTR with burnout curve
            ctr = ctr_curve(day_of_life, net, fmt, net_props["base_ctr"])
            clicks = int(impressions * ctr)

            # Installs from CVR (clicks → installs)
            cpi = net_props["cpi_usd"] * COUNTRY_CPI_MULT[country] * np.random.normal(1.0, 0.15)
            installs = int(spend / max(cpi, 0.1)) if spend > 0 else 0

            rows.append({
                "stat_date":   d.isoformat(),
                "campaign_id": cid,
                "creative_id": cre["creative_id"],
                "network":     net,
                "country":     country,
                "impressions": max(0, impressions),
                "clicks":      max(0, min(clicks, impressions)),
                "spend_usd":   round(spend, 4),
                "installs":    max(0, installs),
            })

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT_DIR / "ad_daily_stats.csv", index=False)
    print(f"  → {len(df):,} rows of daily ad stats")
    return df


# ─── 4. Generate SKAN Postbacks ───────────────────────────────────────────────
def generate_skan_postbacks(
    ad_stats: pd.DataFrame,
    campaigns: pd.DataFrame
) -> pd.DataFrame:
    """
    Simulate SKAN 4.0 postbacks.
    Key SKAN realism:
    - Only a fraction of installs generate postbacks (privacy threshold filtering)
    - Conversion value distribution reflects product monetization
    - SKAN 4 allows up to 3 postbacks per user (fine + 2 coarse)
    - Privacy threshold: if install volume < threshold → no postback or coarse only
    """
    print("Generating SKAN postbacks...")
    rows = []
    camp_map = campaigns.set_index("campaign_id").to_dict("index")

    # Aggregate installs by day/campaign/creative for SKAN bucketing
    agg = (
        ad_stats
        .groupby(["stat_date", "campaign_id", "creative_id", "network", "country"])["installs"]
        .sum()
        .reset_index()
    )

    for _, row in agg.iterrows():
        installs = int(row["installs"])
        if installs == 0:
            continue

        camp = camp_map.get(row["campaign_id"], {})
        country = row["country"]

        # SKAN privacy threshold: low-volume days get coarse/no postback
        if installs < 8:
            privacy = "medium"     # only coarse conversion value
            eligible_frac = 0.6    # not all get through
        elif installs < 25:
            privacy = "low"
            eligible_frac = 0.85
        else:
            privacy = "none"       # fine conversion value available
            eligible_frac = 0.95

        eligible_installs = max(0, int(installs * eligible_frac))
        if eligible_installs == 0:
            continue

        install_date = date.fromisoformat(str(row["stat_date"]))

        # First postback (install window)
        for _ in range(eligible_installs):
            # CV distribution: most users don't convert, some do
            cv_weights = [30, 20, 15, 12, 8, 5, 4, 3] + [1] * 8
            available_cvs = list(range(min(len(cv_weights), 16)))
            cv = random.choices(available_cvs, weights=cv_weights[:len(available_cvs)])[0]

            rows.append({
                "postback_id":       str(uuid.uuid4()),
                "install_date":      install_date.isoformat(),
                "campaign_id":       row["campaign_id"],
                "creative_id":       row["creative_id"],
                "network":           row["network"],
                "country":           country,
                "skan_version":      "4.0",
                "conversion_value":  cv,
                "postback_sequence": 1,
                "privacy_threshold": privacy,
            })

            # Second postback (days 3-7 window) — ~40% of users
            if random.random() < 0.40 and privacy != "medium":
                post2_cv = min(cv + random.randint(0, 8), 63)
                rows.append({
                    "postback_id":       str(uuid.uuid4()),
                    "install_date":      install_date.isoformat(),
                    "campaign_id":       row["campaign_id"],
                    "creative_id":       row["creative_id"],
                    "network":           row["network"],
                    "country":           country,
                    "skan_version":      "4.0",
                    "conversion_value":  post2_cv,
                    "postback_sequence": 2,
                    "privacy_threshold": "low",
                })

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT_DIR / "skan_postbacks.csv", index=False)
    print(f"  → {len(df):,} SKAN postbacks")
    return df


# ─── 5. Generate IAP Events (Revenue) ─────────────────────────────────────────
def generate_iap_events(
    ad_stats: pd.DataFrame,
    campaigns: pd.DataFrame
) -> pd.DataFrame:
    """
    Generate in-app purchase events for installed users.
    Revenue follows a realistic subscription funnel:
    trial → conversion → renewal (with churn at each step).
    This enables LTV / cohort revenue / ROAS calculations.
    """
    print("Generating IAP events...")
    rows = []
    camp_map = campaigns.set_index("campaign_id").to_dict("index")

    # Aggregate installs
    agg = (
        ad_stats
        .groupby(["stat_date", "campaign_id", "creative_id", "network", "country"])["installs"]
        .sum()
        .reset_index()
    )

    product_weights = [0.50, 0.30, 0.15, 0.05]   # weekly, monthly, annual, lifetime
    products = list(IAP_PRODUCTS.keys())

    for _, row in agg.iterrows():
        installs = int(row["installs"])
        if installs == 0:
            continue

        install_date = date.fromisoformat(str(row["stat_date"]))

        # Conversion rates (install → trial → purchase)
        trial_rate     = random.uniform(0.20, 0.35)
        purchase_rate  = random.uniform(0.25, 0.45)   # of trial starters

        n_trials    = int(installs * trial_rate)
        n_purchases = int(n_trials * purchase_rate)

        camp = camp_map.get(row["campaign_id"], {})
        country = row["country"]

        # Trial start events (D0-D3)
        for _ in range(n_trials):
            trial_day = random.randint(0, 3)
            event_date = install_date + timedelta(days=trial_day)
            if event_date > SIM_END:
                continue
            product = random.choices(products, weights=product_weights)[0]
            rows.append({
                "event_id":     str(uuid.uuid4()),
                "install_date": install_date.isoformat(),
                "event_date":   event_date.isoformat(),
                "campaign_id":  row["campaign_id"],
                "creative_id":  row["creative_id"],
                "network":      row["network"],
                "country":      country,
                "event_type":   "trial_start",
                "product_id":   product,
                "revenue_usd":  0.0,
            })

        # Subscription purchase events
        for _ in range(n_purchases):
            purchase_day = random.randint(1, 7)
            event_date = install_date + timedelta(days=purchase_day)
            if event_date > SIM_END:
                continue
            product = random.choices(products, weights=product_weights)[0]
            prod_props = IAP_PRODUCTS[product]
            rows.append({
                "event_id":     str(uuid.uuid4()),
                "install_date": install_date.isoformat(),
                "event_date":   event_date.isoformat(),
                "campaign_id":  row["campaign_id"],
                "creative_id":  row["creative_id"],
                "network":      row["network"],
                "country":      country,
                "event_type":   "subscription_start",
                "product_id":   product,
                "revenue_usd":  prod_props["price"],
            })

            # Simulate renewals within the sim window
            if prod_props["period_days"]:
                renewal_date = event_date + timedelta(days=prod_props["period_days"])
                while renewal_date <= SIM_END and random.random() < prod_props["renew_rate"]:
                    rows.append({
                        "event_id":     str(uuid.uuid4()),
                        "install_date": install_date.isoformat(),
                        "event_date":   renewal_date.isoformat(),
                        "campaign_id":  row["campaign_id"],
                        "creative_id":  row["creative_id"],
                        "network":      row["network"],
                        "country":      country,
                        "event_type":   "subscription_renew",
                        "product_id":   product,
                        "revenue_usd":  prod_props["price"],
                    })
                    renewal_date += timedelta(days=prod_props["period_days"])

    df = pd.DataFrame(rows)
    df.to_csv(OUTPUT_DIR / "iap_events.csv", index=False)
    print(f"  → {len(df):,} IAP events")
    return df


# ─── Main ─────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    print(f"\n{'='*55}")
    print("  iOS UA Synthetic Data Generator")
    print(f"  Simulation: {SIM_START} → {SIM_END} ({SIM_DAYS} days)")
    print(f"{'='*55}\n")

    campaigns  = generate_campaigns()
    creatives  = generate_creatives(campaigns)
    ad_stats   = generate_ad_daily_stats(campaigns, creatives)
    skan       = generate_skan_postbacks(ad_stats, campaigns)
    iap        = generate_iap_events(ad_stats, campaigns)

    print(f"\n{'='*55}")
    print("  All files written to ingestion/data/")
    total_rows = len(campaigns) + len(creatives) + len(ad_stats) + len(skan) + len(iap)
    print(f"  Total rows generated: {total_rows:,}")
    print(f"{'='*55}\n")
    print("Next step: python ingestion/load_to_clickhouse.py")
