#!/bin/bash
# [재실행, 2026-11-20 결정] 한 번에 약 2.5시간
#   bash scripts/07_rerun.sh
# 1) executor가 실행 중 죽었다 다시 생긴 3건을 runs_excluded/로 옮기고 같은 이름으로 다시 측정
# 2) local 3회차 추가 (다른 설정과 반복 수 맞추기)
# 3) (가장 먼저 실행) powermetrics로 P/E코어 사용률을 기록하며 ② scale-up, ③ local을 1회씩 (r7, 시간 분석과 분리)
# 시작할 때 sudo 비밀번호를 한 번 묻는다 (powermetrics용).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -d "$HERE/../m3work" ]; then WORK="${WORK:-$HERE/../m3work}"; else WORK="${WORK:-$HOME/m3work}"; fi
cd "$WORK/yonsei-tpcx-ai-sales-forecasting/M2"
RESULTS="$HERE/../results"; mkdir -p "$RESULTS"

# all (default), timing (no sudo), or power (r7 only).
export RERUN_PHASE="${RERUN_PHASE:-all}"
case "$RERUN_PHASE" in
  all|power) sudo -v ;;
  timing) ;;
  *) echo "Unknown RERUN_PHASE: $RERUN_PHASE" >&2; exit 2 ;;
esac

caffeinate -i bash -c '
set -euo pipefail
B="docker compose exec -T -e COOLDOWN=120"

if [[ "$RERUN_PHASE" != timing ]]; then
# powermetrics를 먼저: sudo 인증이 살아 있을 때 시작해야 한다. 5초 간격 1200회(100분) 후 스스로 끝난다.
echo "##### powermetrics 측정 (r7) $(date "+%F %T")"
sudo -n powermetrics --samplers cpu_power -i 5000 -n 1200 -o "'"$RESULTS"'/powermetrics_r7.log" &
POWER_PID=$!
sleep 5
kill -0 "$POWER_PID" || { echo "powermetrics 시작 실패"; exit 1; }
WINDOWS="'"$RESULTS"'/powermetrics_windows.csv"
printf "run_id,started_epoch,finished_epoch\n" > "$WINDOWS"
power_run() {
  local id=$1 started
  shift
  sleep 120
  kill -0 "$POWER_PID" || { echo "powermetrics stopped early"; exit 1; }
  started=$(date +%s)
  docker compose exec -T -e COOLDOWN=0 -e MODES=separate client docker/m3_resource.sh "$@"
  kill -0 "$POWER_PID" || { echo "powermetrics stopped during $id"; exit 1; }
  printf "%s,%s,%s\n" "$id" "$started" "$(date +%s)" >> "$WINDOWS"
}
for C in 1 2 3 4; do power_run "m3_sf1_yarn_e2c${C}m2g_r7_separate" yarn 2 "$C" 2g 7; done
for N in 1 2 4 8; do power_run "m3_sf1_local${N}_r7_separate" local "$N" 6g 7; done
echo "##### powermetrics 측정 끝 $(date "+%F %T")"
fi
if [[ "$RERUN_PHASE" == power ]]; then exit 0; fi

replace_run() {
  local id=$1 mode=$2
  shift 2
  mkdir -p runs_excluded
  if [[ ! -d "runs_excluded/$id" ]]; then
    mv "runs/$id" runs_excluded/
    if [[ -f "runs/$id.log" ]]; then mv "runs/$id.log" runs_excluded/; fi
  fi
  if [[ ! -f "runs/$id/validation.json" ]]; then
    $B -e MODES="$mode" client docker/m3_resource.sh "$@"
  fi
}
echo "##### 교체 실행 $(date "+%F %T")"
replace_run m3_sf1_yarn_e2c3m2g_r1_separate separate yarn 2 3 2g 1
replace_run m3_sf1_yarn_e1c2m2g_r2_shared shared yarn 1 2 2g 2
replace_run m3_sf1_yarn_e1c2m2g_r3_shared shared yarn 1 2 2g 3

echo "##### local 3회차 $(date "+%F %T")"
for N in 1 2 4 8; do
  if [[ ! -f "runs/m3_sf1_local${N}_r3_separate/validation.json" ]]; then
    $B -e MODES=separate client docker/m3_resource.sh local "$N" 6g 3
  fi
done
pmset -g therm >> therm.log || true
echo "##### 재실행 끝 $(date "+%F %T")"
' 2>&1 | tee -a m3_all.log
echo "다음: bash scripts/05_collect.sh  (그다음 결과 공유)"
