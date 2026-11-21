#!/bin/bash
# Run the isolated 3 GiB executor follow-up on the existing SF1 cluster.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/m3work}"
if [[ ! -d "$WORK" && "$WORK" = "$ROOT/m3work" ]]; then WORK="$HOME/m3work"; fi
PYTHON="${PYTHON:-python3}"
cd "$WORK/yonsei-tpcx-ai-sales-forecasting/M2"
"$PYTHON" -c 'import zstandard'

run() {
  local mode=$1 repeat=$2
  docker compose exec -T -e "MODES=$mode" -e PART=24 -e COOLDOWN=120 client \
    docker/m3_resource.sh yarn 1 2 3g "$repeat"
}

run shared 10
if ! "$PYTHON" - "$ROOT" <<'PY'
import json
import runpy
import sys
from pathlib import Path

run = Path("runs/m3_sf1_yarn_e1c2m3g_r10_shared")
validation = json.loads((run / "validation.json").read_text())
events = runpy.run_path(str(Path(sys.argv[1]) / "scripts/06_spark_event_summary.py"))
row = events["summarize_run"](run)
print("Pilot Spark events:", row, flush=True)
passed = validation["failed"] == 0 and row["failed_tasks"] == 0 and row["executors_added"] == row["peak_active_executors"] == 1
raise SystemExit(0 if passed else 1)
PY
then
  echo "PILOT_REJECTED"
  exit 2
fi
echo "PILOT_PASSED"

for repeat in 11 12 13; do
  if (( repeat % 2 )); then
    run separate "$repeat"
    run shared "$repeat"
  else
    run shared "$repeat"
    run separate "$repeat"
  fi
done
echo "FOLLOWUP_FINISHED"
