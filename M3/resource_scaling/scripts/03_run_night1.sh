#!/bin/bash
# [본 측정 1/2] 반복 1, 2회차: 핵심 + ① scale-out + ② scale-up  (약 4~5시간)
#   bash scripts/03_run_night1.sh
# 시작 전: 전원 연결, 다른 앱 종료, 저전력 모드 끔, (선택) 다른 터미널에서 powermetrics 기록 시작 (README의 P/E 코어 관측 참고)
set -euo pipefail
cd "${WORK:-$HOME/m3work}/yonsei-tpcx-ai-sales-forecasting/M2"
REPS="${REPS:-1 2}"
caffeinate -i bash -c '
set -euo pipefail
X="docker compose exec -T -e COOLDOWN=120 client docker/m3_resource.sh"
S="docker compose exec -T -e COOLDOWN=120 -e MODES=separate client docker/m3_resource.sh"
for R in '"$REPS"'; do
  echo "##### 회차 $R 시작 $(date "+%F %T")"
  $X yarn 1 2 2g $R; $X yarn 2 2 2g $R                                   # 핵심 (두 모드)
  $S yarn 1 1 1g $R; $S yarn 2 1 1g $R; $S yarn 3 1 1g $R; $S yarn 4 1 1g $R   # ① scale-out
  $S yarn 2 1 2g $R; $S yarn 2 3 2g $R; $S yarn 2 4 2g $R                # ② scale-up (e2c2는 핵심과 공유)
  pmset -g therm >> therm.log || true
done
echo "##### 끝 $(date "+%F %T")"
' 2>&1 | tee -a m3_all.log
