#!/bin/bash
# [본 측정 2/2] 반복 3회차 + ③ local 기준선  (약 3~4시간)
#   bash scripts/04_run_night2.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "${WORK:-$HOME/m3work}/yonsei-tpcx-ai-sales-forecasting/M2"
REPS=3 bash "$HERE/03_run_night1.sh"
caffeinate -i bash -c '
set -euo pipefail
S="docker compose exec -T -e COOLDOWN=120 -e MODES=separate client docker/m3_resource.sh"
for N in 1 2 4 8; do
  $S local $N 6g 0      # r0: 로컬 적재가 포함되므로 분석에서 뺀다
  $S local $N 6g 1
  $S local $N 6g 2
done
echo "##### local 끝 $(date "+%F %T")"
' 2>&1 | tee -a m3_all.log
