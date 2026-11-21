#!/bin/bash
# [측정 후] 결과를 하나로 합치고 이 폴더의 results/ 로 복사한다.
#   bash scripts/05_collect.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
if [ -d "$HERE/m3work" ]; then WORK="${WORK:-$HERE/m3work}"; else WORK="${WORK:-$HOME/m3work}"; fi
cd "$WORK/yonsei-tpcx-ai-sales-forecasting/M2"
# 분석 대상: 반복 1~3회차만 (local 적재 r0, P/E 관측 r7, 메모리 시험 r9 제외)
RUNS=$(ls -d runs/m3_*_r[123]_*/ | sed 's:/$::')
echo "$RUNS" | wc -l | xargs echo "run 폴더 수 (초기 41, local 3회차 추가 후 45):"
docker compose exec -T client python3 tools/compare_runs.py $RUNS
mkdir -p "$HERE/results"
cp runs/all_stages.csv "$HERE/results/"
cp m3_all.log "$HERE/results/" 2>/dev/null || true
cp therm.log "$HERE/results/" 2>/dev/null || true
for d in $RUNS; do
  mkdir -p "$HERE/results/runs/$(basename "$d")"
  cp "$d"/metrics.json "$d"/stages.csv "$d"/validation.json "$HERE/results/runs/$(basename "$d")/" 2>/dev/null || true
done
echo "복사 완료: $HERE/results/"
