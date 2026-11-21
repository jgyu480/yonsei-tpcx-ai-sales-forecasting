#!/bin/bash
# M3 1번(자원 확장): SF1 고정, Spark 자원만 바꿔 separate/shared를 같은 조건으로 실행한다.
# M2/docker/ 에 복사한 뒤 client 컨테이너 안에서 실행:
#   docker compose exec client docker/m3_resource.sh yarn  <executors> <cores> <memory> <repeat>
#   docker compose exec client docker/m3_resource.sh local <threads> <driver-memory> <repeat>
# run_cluster.sh와 다른 점
#   - --reingest 없음: 두 모드 모두 이미 만들어진 clean 테이블을 재사용한다(적재 조건 동일).
#   - 실행 순서를 반복 번호마다 바꾼다: 홀수 separate→shared, 짝수 shared→separate.
#   - shuffle partitions를 모든 설정에서 24로 고정한다(M2 e2c3 기본값과 같음). PART=값 으로 변경.
#   - COOLDOWN=120 으로 주면 각 실행 전에 120초 쉰다.
#   - MODES=separate 로 주면 separate만 실행한다(곡선용 추가 설정). 기본은 두 모드 모두.
#   - local 모드는 HDFS가 아닌 로컬 디스크(data/sf1, warehouse_local)를 쓴다.
#     client 컨테이너에는 TPCXAI_WAREHOUSE가 HDFS로 설정돼 있어서 --warehouse를 꼭 따로 준다.
# 사전 조건
#   yarn : load_hdfs.sh 1 후 run_cluster.sh 1 2 3 4g 를 한 번 돌려 clean 테이블 생성(+ M2 점수 확인)
#   local: 첫 local 실행(r0)은 로컬 적재가 포함되므로 측정에서 뺀다.
set -euo pipefail
SF=1
PART="${PART:-24}"
MODES="${MODES:-both}"
COOLDOWN="${COOLDOWN:-0}"   # 실행 전 대기(초). 팬 없는 MacBook Air의 발열 누적을 줄인다.
KIT="--model-python /opt/kitenv/bin/python"
mkdir -p runs

run_pair () {   # $1 tag, $2 repeat, 나머지 = run.py 공통 인자
  local TAG=$1 REP=$2; shift 2
  local ORDER
  if [[ "$MODES" != both ]]; then ORDER="$MODES"
  elif (( REP % 2 == 1 )); then ORDER="separate shared"; else ORDER="shared separate"; fi
  for M in $ORDER; do
    local ID="${TAG}_r${REP}_${M}"
    if (( COOLDOWN > 0 )); then echo "cooldown ${COOLDOWN}s"; sleep "$COOLDOWN"; fi
    echo "=== $ID  ($(date '+%F %T')) ==="
    python3 run.py "$@" --mode "$M" --run-id "$ID" 2>&1 | tee "runs/${ID}.log"
  done
}

case "${1:-}" in
  yarn)
    EX=$2; CORES=$3; MEM=$4; REP=$5
    run_pair "m3_sf${SF}_yarn_e${EX}c${CORES}m${MEM}" "$REP" \
      --data-dir "hdfs://namenode:9000/tpcxai/sf${SF}" --sf "$SF" --master yarn \
      --executors "$EX" --executor-cores "$CORES" --executor-memory "$MEM" \
      --driver-memory 3g --shuffle-partitions "$PART" $KIT ;;
  local)
    N=$2; DMEM=$3; REP=$4
    run_pair "m3_sf${SF}_local${N}" "$REP" \
      --data-dir "file:///workspace/data/sf${SF}" --sf "$SF" --master local --workers "$N" \
      --warehouse /workspace/warehouse_local --driver-memory "$DMEM" \
      --shuffle-partitions "$PART" $KIT ;;
  *)
    sed -n 2,5p "$0"; exit 1 ;;
esac
