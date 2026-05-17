"""
daily_ua_pipeline.py
─────────────────────
Airflow DAG: runs every day at 06:00 UTC.
  1. Loads fresh data from the source (simulate: re-runs the Python generator for yesterday)
  2. Runs all dbt models in dependency order
  3. Sends a Slack alert if any step fails (configure webhook in Airflow Variables)

Demonstrates:
  - SLA monitoring (alert if pipeline takes > 45 minutes)
  - Retry logic (3 retries with exponential backoff)
  - Task dependencies and branching
  - Backfill-compatible design (each run is idempotent)
"""

from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.providers.slack.operators.slack_webhook import SlackWebhookOperator
from airflow.models import Variable

# ─── DAG Default Arguments ────────────────────────────────────────────────────
DEFAULT_ARGS = {
    "owner":            "analytics",
    "depends_on_past":  False,
    "email_on_failure": False,          # We use Slack alerts instead
    "email_on_retry":   False,
    "retries":          3,
    "retry_delay":      timedelta(minutes=5),
    "retry_exponential_backoff": True,  # 5m, 10m, 20m
    "max_retry_delay":  timedelta(minutes=30),
}

# ─── SLA Callback ─────────────────────────────────────────────────────────────
def sla_miss_callback(dag, task_list, blocking_task_list, slas, blocking_tis):
    """Called by Airflow when the pipeline SLA (45 min) is breached."""
    msg = (
        f":warning: *SLA BREACH* on `{dag.dag_id}`\n"
        f"Blocking tasks: `{blocking_task_list}`\n"
        f"Time: {datetime.utcnow().strftime('%Y-%m-%d %H:%M UTC')}"
    )
    # In production, send to Slack via webhook; for now just log
    print(msg)


# ─── DAG Definition ───────────────────────────────────────────────────────────
with DAG(
    dag_id="daily_ua_pipeline",
    description="Daily iOS UA analytics pipeline: ingest → dbt → alert",
    default_args=DEFAULT_ARGS,
    schedule_interval="0 6 * * *",          # 06:00 UTC every day
    start_date=datetime(2024, 10, 1),
    catchup=True,                            # enables backfill
    max_active_runs=1,                       # prevent concurrent runs
    sla_miss_callback=sla_miss_callback,
    tags=["ua", "dbt", "daily"],
) as dag:

    # ── Task 1: Health check — is ClickHouse reachable? ───────────────────────
    health_check = BashOperator(
        task_id="clickhouse_health_check",
        bash_command=(
            "clickhouse-client --host localhost --query 'SELECT 1' "
            "|| (echo 'ClickHouse not reachable'; exit 1)"
        ),
        sla=timedelta(minutes=2),
    )

    # ── Task 2: Load / refresh source data ────────────────────────────────────
    # In production: call AppsFlyer / AppMetrica API for yesterday's data.
    # In the portfolio setup: re-run the generator (idempotent via TRUNCATE in loader).
    load_data = BashOperator(
        task_id="load_raw_data",
        bash_command=(
            "cd /opt/airflow/dags/../.. && "
            "python ingestion/load_to_clickhouse.py"
        ),
        sla=timedelta(minutes=15),
    )

    # ── Task 3: dbt run — staging layer ───────────────────────────────────────
    dbt_staging = BashOperator(
        task_id="dbt_run_staging",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select staging --profiles-dir . "
            "--vars '{\"run_date\": \"{{ ds }}\"}'"
        ),
        sla=timedelta(minutes=10),
    )

    # ── Task 4: dbt run — intermediate layer ──────────────────────────────────
    dbt_intermediate = BashOperator(
        task_id="dbt_run_intermediate",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select intermediate --profiles-dir ."
        ),
        sla=timedelta(minutes=10),
    )

    # ── Task 5: dbt run — marts layer ─────────────────────────────────────────
    dbt_marts = BashOperator(
        task_id="dbt_run_marts",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt run --select marts --profiles-dir ."
        ),
        sla=timedelta(minutes=15),
    )

    # ── Task 6: dbt test — run all data quality tests ─────────────────────────
    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=(
            "cd /opt/airflow/dags/../../dbt && "
            "dbt test --profiles-dir ."
        ),
        sla=timedelta(minutes=10),
    )

    # ── Task 7: Success notification ──────────────────────────────────────────
    # Requires: airflow-provider-slack, SLACK_WEBHOOK_URL in Airflow Variables
    notify_success = BashOperator(
        task_id="notify_success",
        bash_command=(
            "echo 'Pipeline completed successfully for {{ ds }}. "
            "Marts are ready for BI refresh.'"
            # In production, replace with SlackWebhookOperator:
            # SlackWebhookOperator(
            #     task_id="notify_success",
            #     slack_webhook_conn_id="slack_ua_alerts",
            #     message=f":white_check_mark: UA pipeline completed for {{{{ ds }}}}",
            # )
        ),
        trigger_rule="all_success",
    )

    # ── Task 8: Failure alert ──────────────────────────────────────────────────
    notify_failure = BashOperator(
        task_id="notify_failure",
        bash_command=(
            "echo 'ALERT: Pipeline FAILED for {{ ds }}. Check Airflow logs.'"
        ),
        trigger_rule="one_failed",
    )

    # ─── Task Dependencies (DAG topology) ─────────────────────────────────────
    #
    #  health_check
    #       │
    #  load_data
    #       │
    #  dbt_staging
    #       │
    #  dbt_intermediate
    #       │
    #  dbt_marts
    #       │
    #  dbt_test
    #     / \
    # success fail
    #
    health_check >> load_data >> dbt_staging >> dbt_intermediate >> dbt_marts >> dbt_test
    dbt_test >> [notify_success, notify_failure]
