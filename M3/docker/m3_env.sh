# 2번 축(데이터 확장) 측정 함수. client 컨테이너 안에서 불러온다:
#   docker compose exec client bash
#   source /m3/docker/m3_env.sh
# 실행 결과는 /m3/runs/<run_id>/ (= M3/runs, gitignore). M2/runs 는 쓰지 않는다.
# 실행 이름은 1번 축(m3-sy, m3_resource.sh)과 같은 형식: m3_sf<SF>_yarn_e<EX>c<C>m<MEM>_r<REP>_<mode>
# 측정 조건(M3_PLAN.md 4·5.7절): 두 모드 모두 --reingest 없음, 회차마다 순서 교대, shuffle partitions 24 고정.

cd /workspace                      # run.py, Derby metastore(metastore_db/) 는 M2 쪽
export M3RUNS=/m3/runs
mkdir -p "$M3RUNS"
KIT=/opt/kitenv/bin/python
PART=${PART:-24}

_m3one() {   # _m3one <run_id> <run.py 인자...>
  local ID=$1; shift
  if [ -e "$M3RUNS/$ID" ]; then echo "이미 있음: $M3RUNS/$ID (반복 번호를 바꿔서 다시)"; return 1; fi
  echo "=== $ID  ($(date '+%F %T')) ==="
  python3 run.py "$@" --run-id "$ID" --runs-dir "$M3RUNS" 2>&1 | tee "$M3RUNS/$ID.log"
  local rc=${PIPESTATUS[0]}
  m3check "$ID"
  [ "$rc" -eq 0 ] || echo "!!! $ID 실패 (exit $rc). 다음 실행으로 넘어가지 않음"
  return "$rc"
}

m3run() {    # m3run <SF> <executors> <반복> <먼저 돌릴 모드: separate|shared>
  local SF=$1 EX=$2 REP=$3 FIRST=$4 ORDER M
  local C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master yarn --executors $EX --executor-cores 3 --executor-memory 4g --driver-memory 3g --shuffle-partitions $PART --model-python $KIT"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do _m3one "m3_sf${SF}_yarn_e${EX}c3m4g_r${REP}_${M}" $C --mode "$M" || return 1; done
}

m3local() {  # m3local <SF> <반복> <먼저 돌릴 모드>   (선택 묶음 C)
  local SF=$1 REP=$2 FIRST=$3 ORDER M
  local C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master local --workers 6 --driver-memory 8g --shuffle-partitions $PART --model-python $KIT"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do _m3one "m3_sf${SF}_local6_r${REP}_${M}" $C --mode "$M" || return 1; done
}

m3warm() {   # m3warm <SF>   clean 테이블 적재만(분석 제외). m3_load.sh 뒤에 SF마다 한 번
  local SF=$1
  _m3one "m3_sf${SF}_warmup" --data-dir "hdfs://namenode:9000/tpcxai/sf$SF" --sf "$SF" --master yarn \
    --executors 2 --executor-cores 3 --executor-memory 4g --driver-memory 3g --shuffle-partitions "$PART" \
    --model-python "$KIT" --mode separate --reingest --workloads uc03
}

m3check() {  # m3check <run_id>   검증 실패 수와 executor 추가 수(2개 설정에서 2 초과 = 교체, 5.6절)
  local ID=$1 D="$M3RUNS/$1" n=0 f
  for f in "$D"/spark-events/*; do
    [ -e "$f" ] || continue
    case "$f" in
      *.zstd|*.zst) if command -v zstd >/dev/null; then n=$((n + $(zstd -dc "$f" | grep -c '"Event":"SparkListenerExecutorAdded"')));
                    else n="?(zstd 없음: History Server로 확인)"; break; fi ;;
      *.lz4|*.snappy) n="?(압축: History Server로 확인)"; break ;;
      *) n=$((n + $(grep -c '"Event":"SparkListenerExecutorAdded"' "$f"))) ;;
    esac
  done
  echo "[m3check] $ID  $(grep -h 'checks failed' "$M3RUNS/$ID.log" 2>/dev/null | tail -1)  executors_added=$n"
  echo "$(date '+%F %T'),$ID,$n" >> "$M3RUNS/executor_check.csv"
}

m3history() {  # m3history <패턴, 예: 'm3_sf3_*'>   http://localhost:4040 (Ctrl+C 종료). M2 history_server.sh와 같고 경로만 /m3/runs
  local L=/tmp/spark-history d
  rm -rf "$L" && mkdir -p "$L"
  for d in "$M3RUNS"/${1:-m3_sf*}/spark-events/*; do [ -e "$d" ] && cp -r "$d" "$L/"; done
  local SH; SH="$(python3 -c 'import pyspark, os; print(os.path.dirname(pyspark.__file__))')"
  SPARK_HISTORY_OPTS="-Dspark.history.fs.logDirectory=file://$L -Dspark.history.ui.port=4040" \
    "$SH/bin/spark-class" org.apache.spark.deploy.history.HistoryServer
}

echo "m3_env: m3run <SF> <EX> <REP> <first>, m3warm <SF>, m3local, m3check <id>, m3history <pattern>  (runs -> $M3RUNS)"
