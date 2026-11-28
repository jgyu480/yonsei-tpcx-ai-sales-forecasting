#!/bin/bash
# From the project folder after 07_rerun.sh succeeds: bash scripts/10_prepare_results.sh
# Requires Python packages matplotlib and zstandard.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/m3work}"
if [ ! -d "$WORK" ] && [ "$WORK" = "$ROOT/m3work" ]; then
  WORK="$HOME/m3work"
fi
export WORK
M2="$WORK/yonsei-tpcx-ai-sales-forecasting/M2"
PYTHON="${PYTHON:-python3}"
RESULTS="$ROOT/results"
REPORT_STABILITY="${REPORT_STABILITY:-0}"
DRAFT="$(mktemp -d)"
trap 'rm -rf "$DRAFT"' EXIT

bash "$ROOT/scripts/05_collect.sh"
"$PYTHON" "$ROOT/scripts/06_spark_event_summary.py" "$DRAFT/spark_event_summary.csv" --runs "$M2/runs"
cp "$RESULTS/all_stages.csv" "$DRAFT/"
"$PYTHON" - "$RESULTS" "$DRAFT" "$REPORT_STABILITY" "$ROOT/scripts/08_summarize.py" <<'PY'
import csv, json, re, runpy, sys
from pathlib import Path
results, draft = map(Path, sys.argv[1:3])
allow = sys.argv[3] == '1'
excluded = set()
with (draft / "spark_event_summary.csv").open() as f:
    rows = list(csv.DictReader(f))
with (draft / "all_stages.csv").open() as f:
    reader = csv.DictReader(f)
    stage_rows, fields = list(reader), reader.fieldnames
    stages = {row["run_id"] for row in stage_rows}
expected = runpy.run_path(sys.argv[4])["planned_run_ids"]()
event_ids = {row["run_id"] for row in rows}
if len(rows) != len(event_ids) or event_ids != stages or stages != expected:
    raise SystemExit(
        f"Expected {len(expected)} planned runs. "
        f"Missing stages: {sorted(expected - stages)}; unexpected stages: {sorted(stages - expected)}; "
        f"missing events: {sorted(expected - event_ids)}; unexpected events: {sorted(event_ids - expected)}; "
        f"duplicate event rows: {len(rows) - len(event_ids)}"
    )
for row in rows:
    run = row["run_id"]
    p = results / "runs" / run
    validation = json.loads((p / "validation.json").read_text())
    if validation["run_id"] != run or validation["failed"] != 0:
        raise SystemExit(f"Validation failed for {run}")
    for name in ("metrics.json", "stages.csv"):
        if not (p / name).stat().st_size:
            raise SystemExit(f"Empty {name} for {run}")
    match = re.search(r"_yarn_e([1-4])c", run)
    if match:
        expected_executors = int(match.group(1))
        if any(int(row[k]) != expected_executors for k in ("executors_added", "peak_active_executors")):
            if not allow or not re.fullmatch(r"m3_sf1_yarn_e1c2m2g_r[23]_shared", run):
                raise SystemExit(f"Executor count differs from request or an executor was replaced: {run}")
            excluded.add(run)
if excluded:
    with (draft / "all_stages.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(row for row in stage_rows if row["run_id"] not in excluded)
    print("Excluded from timing due to executor replacement:", ", ".join(sorted(excluded)))
for row in rows:
    row["timing_eligible"] = int(row["run_id"] not in excluded)
    row["timing_exclusion_reason"] = "" if row["timing_eligible"] else "executor_replacement"
with (draft / "spark_event_summary.csv").open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=list(rows[0]))
    writer.writeheader()
    writer.writerows(rows)
print(f"Eligible for timing: {len(stages) - len(excluded)} of {len(expected)} runs")
print(f"Verified {len(expected)} measured runs and validation outputs; timing eligibility checked against requested executor counts")
PY
summary_args=()
plot_args=()
if [[ "$REPORT_STABILITY" == 1 ]]; then
  summary_args=(--allow-partial)
  plot_args=(--report-stability-limit)
fi
"$PYTHON" "$ROOT/scripts/08_summarize.py" "$DRAFT" "$DRAFT/summary_by_config.csv" ${summary_args[@]+"${summary_args[@]}"}
"$PYTHON" "$ROOT/scripts/09_plot.py" "$DRAFT/summary_by_config.csv" "$DRAFT/figures" ${plot_args[@]+"${plot_args[@]}"}
cp "$DRAFT"/{summary_by_config,spark_event_summary}.csv "$RESULTS/"
mkdir -p "$ROOT/figures"
cp "$DRAFT"/figures/*.png "$ROOT/figures/"
