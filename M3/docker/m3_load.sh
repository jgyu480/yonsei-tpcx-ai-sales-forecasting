#!/bin/bash
# client 컨테이너 안: M3 데이터(/m3/m3data/sf<SF>)를 HDFS /tpcxai/sf<SF> 에 올린다.
# M2/docker/load_hdfs.sh 와 명령이 같고 원본 폴더만 다르다(M2는 /workspace/data/sf<SF>).
# HDFS 경로가 같으므로 run.py 인자(--data-dir hdfs://namenode:9000/tpcxai/sf<SF>)는 M2와 같다.
#   docker compose exec client /m3/docker/m3_load.sh <SF>
set -euo pipefail
SF="${1:?usage: m3_load.sh <SF>}"
SRC="/m3/m3data/sf${SF}"
DST="/tpcxai/sf${SF}"
OUT=/m3/runs; mkdir -p "$OUT"

for f in training/order.csv training/lineitem.csv serving/order.csv scoring/order_labels.csv; do
  [ -f "$SRC/$f" ] || { echo "없음: $SRC/$f (M3_PLAN.md 5.0절)"; exit 1; }
done

echo "waiting for 2 live DataNodes ..."
until [ "$(hdfs dfsadmin -report 2>/dev/null | grep -c '^Name:')" -ge 2 ]; do sleep 3; done
hdfs dfs -mkdir -p "$DST" /user/hive/warehouse /user/root /spark

echo "uploading $SRC -> hdfs://namenode:9000$DST  ($(date '+%F %T'))"
time hdfs dfs -put -f "$SRC/training" "$SRC/serving" "$SRC/scoring" "$DST/"

# Spark jars for the YARN containers (M2와 같음)
J="$(python3 -c 'import pyspark, os; print(os.path.dirname(pyspark.__file__))')/jars"
(cd "$J" && zip -q -r /tmp/spark-jars.zip .)
hdfs dfs -put -f /tmp/spark-jars.zip /spark/spark-jars.zip

# 입력 크기 기록 (M3_PLAN.md 5.7절)
{ date '+%F %T'; hdfs dfs -du "$DST/*"; hdfs dfs -du -s -h "$DST"; } | tee "$OUT/hdfs_sf${SF}.txt"
hdfs dfsadmin -report | grep -E "^Name:|DFS Used:|DFS Remaining:" | head -9
