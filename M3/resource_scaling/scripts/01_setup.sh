#!/bin/bash
# [처음 한 번] 코드 받기 → SF1 데이터 복사 → 이미지 빌드 → HDFS 적재 → 워밍업 실행 (약 40분)
#   bash scripts/01_setup.sh
# 바꿀 수 있는 값 (환경변수)
#   WORK     : 작업 폴더 (기본 ~/m3work).
#   TARBALL  : SF1 압축 파일 (기본: 이 폴더의 sf1_data.tar.gz). 있으면 이것을 우선 쓴다.
#   SF1_SRC  : TARBALL이 없을 때 쓸 SF1 데이터 폴더 (training/ serving/ scoring/ 이 들어 있는 곳)
#   SKIP_SHA=1 : 압축 파일 SHA-256 검사를 건너뜀 (파일이 다시 만들어진 경우에만)
#   WARM_MEM : 워밍업 executor 메모리 (기본 2g, MacBook Air 16GB 기준)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HOME/m3work}"
TARBALL="${TARBALL:-$HERE/../sf1_data.tar.gz}"
SHA_EXPECTED=51366aeabf4ffeb4b57d30099c1ea14edc1d804a13cb8971879c9302d6e3c3aa   # M2 README 13.1절
SF1_SRC="${SF1_SRC:-}"
WARM_MEM="${WARM_MEM:-2g}"
COMMIT=2239421          # 실험 설계 시점의 M2 코드 (2026-11-17). 모든 측정은 이 버전으로 한다.

mkdir -p "$WORK"; cd "$WORK"
if [ ! -d yonsei-tpcx-ai-sales-forecasting ]; then
  git clone https://github.com/jgyu480/yonsei-tpcx-ai-sales-forecasting.git
fi
cd yonsei-tpcx-ai-sales-forecasting
git checkout -q "$COMMIT"
cd M2

if [ ! -f data/sf1/training/lineitem.csv ]; then
  if [ -f "$TARBALL" ]; then
    if [ "${SKIP_SHA:-0}" != 1 ]; then
      echo "SHA-256 확인: $TARBALL"
      GOT=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
      if [ "$GOT" != "$SHA_EXPECTED" ]; then
        echo "SHA-256 불일치: $GOT (기대 $SHA_EXPECTED)"
        echo "파일이 손상됐거나 다른 버전이다. M2 담당자에게 확인 후, 맞는 파일이면 SKIP_SHA=1 로 다시 실행."
        exit 1
      fi
    fi
    echo "압축 해제: $TARBALL -> M2/ (data/sf1/ 생성)"
    tar -xzf "$TARBALL"
  else
    if [ -z "$SF1_SRC" ] || [ ! -d "$SF1_SRC" ]; then
      echo "SF1 데이터를 찾지 못했습니다. TARBALL 또는 SF1_SRC를 지정하세요." >&2
      exit 1
    fi
    echo "SF1 데이터 복사: $SF1_SRC -> data/sf1"
    mkdir -p data && cp -R "$SF1_SRC" data/sf1
  fi
fi
for f in training/lineitem.csv training/order.csv serving/lineitem.csv scoring/order_labels.csv; do
  [ -f "data/sf1/$f" ] || { echo "없음: data/sf1/$f  (README의 자원 확장 실험 실행 참고)"; exit 1; }
done

cp "$HERE/m3_resource.sh" docker/ && chmod +x docker/m3_resource.sh

docker compose build
docker compose up -d
docker compose exec -T client docker/load_hdfs.sh 1
docker compose exec -T client docker/run_cluster.sh 1 2 2 "$WARM_MEM"

echo
echo "=== 워밍업 점수 (기대값: msle 4.01xx, accuracy 0.69xx 가 각각 두 줄) ==="
grep -h -E "msle|accuracy" runs/sf1_yarn_e2c2_kit_*.log
echo "다음: bash scripts/02_smoke_test.sh"
