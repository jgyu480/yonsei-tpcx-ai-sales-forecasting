#!/bin/bash
# [본 측정 전 한 번] 메모리가 가장 빡빡한 두 설정을 1회씩 돌려 OOM이 없는지 확인 (약 20분)
#   bash scripts/02_smoke_test.sh
# 실행 중 다른 터미널에서:  docker stats  → 컨테이너 메모리 합계가 Docker 한도(12GB)에 얼마나 가까운지 본다.
set -euo pipefail
cd "${WORK:-$HOME/m3work}/yonsei-tpcx-ai-sales-forecasting/M2"
S="docker compose exec -T -e MODES=separate client docker/m3_resource.sh"
$S yarn 4 1 1g 9
$S yarn 2 4 2g 9
echo
grep -h "checks failed" runs/m3_sf1_yarn_e4c1m1g_r9_separate.log runs/m3_sf1_yarn_e2c4m2g_r9_separate.log
echo "두 줄 모두 'checks failed: 0' 이면 통과. 시험 결과(r9)는 측정에 쓰지 않는다:"
echo "  rm -rf runs/m3_*_r9_*"
