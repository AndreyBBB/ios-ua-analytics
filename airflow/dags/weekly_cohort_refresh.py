"""
weekly_cohort_refresh.py
─────────────────────────
Airflow DAG: runs every Monday at 07:00 UTC.
Performs a full historical backfill of cohort-dependent models.

Why a separate weekly DAG?
  Cohort revenue (LTV) accumulates over 30+ days. A user who installed
  on Oct 1 will still be generating revenue events in November.
  The daily DAG does incremental updates, but weekly we do a full recalculation
  of the last 45 days to catch late-arriving revenue events and subscription renewals.

Demonstrates:
  - Scheduled backfill logic (BACKFILL_WINDOW_DAYS)
  - dbt --full-refresh for selected models
  - Sequential execution with clear task graph
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator

BACKFILL_WINDOW_DAYS = 45    # recalculate cohorts that installed in the last 45 days

DEFAULT_ARGS = {
    "owner":            "analytics",
    "depends_on_past":  False,
    "retries":          2,
    "retry_delay":      timedelta(minutes=10),
    "email_on_failure": False,
}

with DAG(
    dag_id="weekly_cohort_refresh",
    description="Full historical recalculation of cohort revenue marts (handles late revenue events)",
    default_args=DEFAULT_ARGS,
    schedule_interval="0 7 * * 1",      # Every Monday 07:00 UTC
    start_date=datetime(2024, 10, 7),
    catchup=False,                       # Don't backfill past runs
    max_active_runs=1,
    tags=["ua", "dbt", "cohort", "weekly"],
) as dag:

    # ── Task 1: Full-refresh intermediate cohort models ────────────────────────
    # --full-refresh drops and recreates the table (not incremental)
    refresh_cohort_installs = BashOperator(
        task_id="refresh_int_cohort_installs",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select int_cohort_installs --full-refresh --profiles-dir ."
        ),
        sla=timedelta(minutes=20),
    )

    refresh_cohort_revenue = BashOperator(
        task_id="refresh_int_cohort_revenue",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select int_cohort_revenue --full-refresh --profiles-dir ."
        ),
        sla=timedelta(minutes=20),
    )

    # ── Task 2: Full-refresh all cohort-dependent marts ───────────────────────
    refresh_mart_cohort = BashOperator(
        task_id="refresh_mart_cohort_analysis",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select mart_cohort_analysis mart_unit_economics --full-refresh --profiles-dir ."
        ),
        sla=timedelta(minutes=20),
    )

    # ── Task 3: Also refresh the incremental creative burnout mart ─────────────
    # The burnout mart uses delete+insert incremental — full-refresh recreates it cleanly
    refresh_mart_burnout = BashOperator(
        task_id="refresh_mart_creative_burnout",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select mart_creative_burnout --full-refresh --profiles-dir ."
        ),
        sla=timedelta(minutes=15),
    )

    # ── Task 4: Run all tests after refresh ───────────────────────────────────
    run_tests = BashOperator(
        task_id="dbt_test_all",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt test --profiles-dir ."
        ),
        sla=timedelta(minutes=15),
    )

    notify = BashOperator(
        task_id="notify_completion",
        bash_command="echo 'Weekly cohort refresh complete for week of {{ ds }}'",
        trigger_rule="all_success",
    )

    # ─── Dependencies ─────────────────────────────────────────────────────────
    (
        refresh_cohort_installs
        >> refresh_cohort_revenue
        >> [refresh_mart_cohort, refresh_mart_burnout]
        >> run_tests
        >> notify
    )
