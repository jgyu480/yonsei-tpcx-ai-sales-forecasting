# M3 계획 (Team7, TPCx-AI UC03 + UC08) — 최종본 (11/21)

M1 보고서, M2 보고서, 저장소 `M2/`(커밋 2239421, 11/17)의 README·`docker/run_cluster.sh`·`docker/load_hdfs.sh`·`run.py`를 읽고 정리했다.
**측정 완료 11/26(목), 제출 12/3(목).**

## 1. 목표

- 수업 요구사항: Milestone 3 = "Performance Analysis w/ Scalability Test" (보고서 + 5분 발표).
- 팀의 질문(M1부터): UC03과 UC08이 같은 조인(Order ⋈ Lineitem ⋈ Product)을 쓰는데, 각자 조인(separate)과
  한 번 조인해 저장 후 공유(shared) 중 어느 쪽이 나은가, 그 답이 규모에 따라 바뀌는가.
- M1 표 5의 세 비교를 채운다: 단계별 비용, 데이터 증가(SF 변경), 자원 증가(executor 변경).
- M2가 남긴 숙제: 반복 측정(각 3회), 두 모드의 적재·캐시 조건 맞추기.
- M2 결과(SF1, executor 2 × 3코어 4GB, 키트 버전 모델, 각 1회): 작업 시간 separate 292초, shared 354초, MSLE 4.01, accuracy 0.693.
  shared만 `--reingest`로 적재부터 하고 먼저 실행해서 조건이 같지 않았다.

## 2. 기계 역할

| 기계 | 역할 | 이유 |
| --- | --- | --- |
| Mac (M4 Pro 24GB, Docker 16GB) | **모든 측정** | M2와 같은 기계. 측정 기계가 바뀌면 SF1부터 다시 재야 하고, arm64와 x86 결과는 섞어 비교할 수 없다 |
| x86 Ubuntu 26.04 VM (VMware, 4 vCPU, RAM 7.2GiB, 디스크 여유 77GB) | **데이터 생성 전용** (SF3, SF10) | PDGF는 x86 + Java 8에서만 돈다. Docker 16GB가 필요한 클러스터 측정에는 메모리가 부족하다 |

## 3. 데이터 생성 (VM)

### 키트 드라이버를 직접 돌리지 않는다

- 키트 드라이버의 `-sf`는 데이터 용량(GB)이고 PDGF 값으로 바뀐다(3 → 2.125, 10 → 12.875). 드라이버로 만들면 M2의 SF1(PDGF `-sf 1`)과 비교할 수 없다.
- README 3절 명령이 드라이버(`driver/tpcxai-driver/data_generation.py`)와 같은 시드·옵션을 PDGF에 직접 준다. "키트 드라이버 기준"이란 이 시드·옵션을 쓴다는 뜻이다.
- `docker/gen_data.sh`(Docker)의 x86 실행은 확인되지 않았다. M2 담당자가 확인한 **Java 직접 실행**으로 한다.

| | `-sf` | `SF_TRAINING` | `MY_SEED` | 크기 |
| --- | --- | --- | --- | --- |
| 학습 | SF | (없음) | 1234 | SF에 따라 커짐 |
| 서빙 | SF | SF | 1235 | SF에 따라 커짐 |
| 채점 | **1 고정** | SF | **1234 + SF** (SF3이면 1237) | **SF와 무관** (order 520,000) |

채점 데이터 크기가 고정이므로 데이터 확장 분석은 train·serve 단계로 하고, score 단계 시간이 거의 같은 이유를 보고서에 적는다.

### VM 경로

| 무엇 | 경로 |
| --- | --- |
| 저장소 (VMware 공유 폴더) | `/mnt/hgfs/minji/Works/26-2-Yonsei/yonsei-tpcx-ai-sales-forecasting` |
| Java 8 (Temurin 8u432), 키트 v2.0.0 | `/home/minji/Applications/m3/` 아래 |
| 생성 결과 | `/home/minji/m3data/data/sf<SF>/` (로컬 디스크. 공유 폴더에 쓰지 않는다) |

### 순서 (M2 담당자 안내 우선: README 3절 PDGF 명령을 그대로, 한 단계씩)

```bash
# 0) 저장소를 최신으로 (README 3절이 11/17에 업데이트됨)
cd /mnt/hgfs/minji/Works/26-2-Yonsei/yonsei-tpcx-ai-sales-forecasting && git pull
sed -n '/## 3\./,/## 4\./p' M2/README.md          # 아래 명령과 같은지 확인

# 1) 경로 확인
export J=$(ls -d ~/Applications/m3/jdk8u*/bin/java | head -1); $J -version     # 1.8.0_432
export KIT=$(dirname "$(find ~/Applications/m3 -maxdepth 3 -type d -name data-gen | head -1)"); ls $KIT/lib/pdgf/pdgf.jar

# 2) 생성 스크립트 (README 3절 명령과 동일, 출력 폴더 R만 SF별로 분리)
cat > ~/Applications/m3/gen_sf.sh <<'SH'
#!/bin/bash
set -euo pipefail
SF=${1:?usage: gen_sf.sh <SF>}; : "${J:?}"; : "${KIT:?}"
R=$HOME/m3data/data/sf$SF
cd "$KIT/data-gen"
O="-l config/tpcxai-schema.xml -l config/tpcxai-generation.xml -ns"
T="order lineitem product store_dept"
run() { printf '\nYES\n' | "$J" -Djava.awt.headless=true -Xmx4g -jar ../lib/pdgf/pdgf.jar $O "$@"; }
mkdir -p "$R/training" "$R/serving" "$R/scoring"
echo "[$(date)] training start"; run -sf $SF -sp MY_SEED 1234 -sp includeLabels 1.0 -sp TTVF 1.0 -s $T -output "\"$R/training/\""
echo "[$(date)] serving start";  run -sf $SF -sp SF_TRAINING $SF -sp MY_SEED 1235 -sp includeLabels 0.0 -sp TTVF 0.1 -s $T -output "\"$R/serving/\""
echo "[$(date)] scoring start";  run -sf 1 -sp SF_TRAINING $SF -sp MY_SEED $((1234 + SF)) -sp includeLabels 2.0 -sp TTVF 0.1 -s $T order_weekly_sales -output "\"$R/scoring/\""
echo "[$(date)] done"; wc -l "$R"/*/*.csv
SH
chmod +x ~/Applications/m3/gen_sf.sh

# 3) SF3 생성 (백그라운드, 로그로 확인)
nohup ~/Applications/m3/gen_sf.sh 3 > ~/m3data/gen_sf3.log 2>&1 &
tail -f ~/m3data/gen_sf3.log        # Ctrl+C는 보기만 멈춤

# 4) 확인: training order 약 1,560만 줄(SF1 520만의 3배, 추정), scoring order 520,000 줄 (+헤더 1줄)

# 5) 압축 → 공유 폴더 → Mac
cd ~/m3data && tar -czf sf3_data.tar.gz data/sf3 && sha256sum sf3_data.tar.gz
cp sf3_data.tar.gz /mnt/hgfs/minji/Works/26-2-Yonsei/      # 저장소 밖에 둔다 (데이터는 저장소에 올리지 않음)
#    Mac: M2/ 에서 tar -xzf sf3_data.tar.gz → data/sf3/, shasum -a 256 이 VM 값과 같은지 확인

# 6) (선택) SF1 환경 검증과 SF10은 SF3 전송 뒤에. 동시에 두 개 돌리지 않는다(메모리 약 4GB)
#    SF1 검증: gen_sf.sh 1 후 Mac data/sf1 과 md5 비교 (M2 담당자는 같은 Java로 14개 파일 일치 확인함)
```

- 생성 중에는 VS Code, 브라우저를 닫고 VM·PC 절전을 끈다.
- 단계별 시작 시각이 로그에 남는다. 보고서의 데이터 준비 비용으로 쓴다.
- **대체 규칙**: 11/22(일)까지 SF3가 Mac에 없으면 SF1을 주문 ID 기준 25%·50%·100%로 샘플링해 데이터 확장을 대신한다.

## 4. 코드 확인 결과 (측정 방법에 영향)

1. `run_cluster.sh`는 항상 **shared를 `--reingest`로 먼저**, separate를 그다음에 돌린다. M2의 조건 불일치가 여기서 나왔다.
   → 반복 측정은 `run.py`를 직접 호출해 **두 모드 모두 `--reingest` 없이**(clean 테이블 재사용, load 0초) 돌리고, 반복마다 순서를 바꾼다.
   shared의 조인 저장은 load가 아니라 preprocess에 들어가므로, 이 조건이 공정한 비교다.
2. clean 테이블은 SF 라벨별 Hive DB(`sf1_clean`, `sf3_clean`)에 생긴다. SF마다 한 번 적재(워밍업)한 뒤 측정한다.
3. executor 1개 실행(묶음 B)은 그대로 된다. 워커당 YARN 6GB·4 vcore라 executor 4g(+오버헤드)·3코어가 워커 하나에 들어간다.
   executor를 3개 이상으로 늘리려면 크기를 줄여야 해서 조건이 섞이므로, executor 1개 vs 2개로 비교한다.
4. 로컬 모드(묶음 C)는 `run.py --master local --workers N`. client 컨테이너 안에서 HDFS 데이터를 읽게 돌린다.
   **첫 실행으로 동작을 확인**한다(HDFS warehouse와 local master 조합은 M2에서 돌려 보지 않았다).
5. 최대 메모리: Spark executor·셔플·스필은 `spark-events/`(History Server), 모델 프로세스를 포함한 컨테이너 메모리는 Mac에서 `docker stats`를 기록한다.

## 5. 측정 (Mac)

### 준비와 SF1 재현 (11/21)

```bash
cd M2 && git pull
docker compose build && docker compose up -d
docker compose exec client docker/load_hdfs.sh 1
docker compose exec client docker/run_cluster.sh 1 2 3 4g    # 약 12분. clean 테이블 적재(워밍업)도 겸한다
```

MSLE 4.01, accuracy 0.693이면 환경이 맞다(`results/`의 같은 이름 폴더와 비교). 이 두 실행은 재현 확인용이고 분석에는 넣지 않는다.

### 측정 함수 (client 컨테이너 안: `docker compose exec client bash`)

```bash
KIT=/opt/kitenv/bin/python
m3run() {   # m3run <SF> <executors> <반복> <먼저 돌릴 모드>
  SF=$1; EX=$2; REP=$3; FIRST=$4
  C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master yarn --executors $EX --executor-cores 3 --executor-memory 4g --driver-memory 3g --model-python $KIT"
  TAG="sf${SF}_yarn_e${EX}c3_r${REP}"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do python3 run.py $C --mode $M --run-id "${TAG}_kit_$M" 2>&1 | tee "runs/${TAG}_kit_$M.log"; done
}
m3local() { # m3local <SF> <반복> <먼저 돌릴 모드>
  SF=$1; REP=$2; FIRST=$3
  C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master local --workers 6 --driver-memory 8g --model-python $KIT"
  TAG="sf${SF}_local6_r${REP}"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do python3 run.py $C --mode $M --run-id "${TAG}_kit_$M" 2>&1 | tee "runs/${TAG}_kit_$M.log"; done
}
```

`--workers 6`은 클러스터의 총 코어(2 × 3)에 맞춘 값이다.

### 메모리 기록 (Mac 터미널, `M2/`에서 측정하는 동안 계속)

```bash
while true; do docker stats --no-stream --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' | sed "s/^/$(date +%s),/"; sleep 5; done >> runs/docker_stats.csv
```

### 묶음

| 묶음 | 명령 | 실행 수 | 예상 기계 시간 | 답하는 질문 |
| --- | --- | --- | --- | --- |
| A. SF1 기준선 | `m3run 1 2 1 separate`, `m3run 1 2 2 shared`, `m3run 1 2 3 separate` | 6 | 약 35분 | 단계별 비용, 조건을 맞춘 separate vs shared |
| B. 자원 확장 | `m3run 1 1 1 separate`, `m3run 1 1 2 shared`, `m3run 1 1 3 separate` | 6 | 약 45분 | executor 1 → 2 speedup |
| C. 로컬 기준선 | `m3local 1 1 separate`, `m3local 1 2 shared`, `m3local 1 3 separate` | 6 | 약 1시간 | 클러스터 vs 단일 프로세스 |
| D. 데이터 확장 | 워밍업 후 `m3run 3 2 1 separate`, `m3run 3 2 2 shared`, `m3run 3 2 3 separate` | 6 | 약 1.5~2시간 | SF1 → SF3 증가 비율, shared가 유리해지는가 |
| (선택) SF10 | 워밍업 후 `m3run 10 2 1 separate` | 1~2 | 1시간 이상 | 메모리 한계 지점 |

SF3·SF10 워밍업(적재만, 결과는 분석에서 제외):

```bash
docker compose exec client docker/load_hdfs.sh 3
# client 컨테이너 안
python3 run.py --data-dir hdfs://namenode:9000/tpcxai/sf3 --sf 3 --master yarn --executors 2 --executor-cores 3 --executor-memory 4g \
  --driver-memory 3g --model-python /opt/kitenv/bin/python --mode separate --reingest --workloads uc03 --run-id sf3_warmup
```

예상 시간은 M2 SF1 실측에서 비례로 낸 추정이다.

### 측정 규칙

- Mac 한 대에서, 전원 연결, 다른 프로그램 종료, 한 번에 하나씩(Derby 메타스토어 제약).
- 같은 이름으로 다시 돌리면 `already exists`로 멈춘다. 실패한 실행은 반복 번호를 바꿔(예: `r4`) 다시 돌린다.
- 기록: `stages.csv`, `metrics.json`(행 수), `spark-events/`, `runs/docker_stats.csv`, 입력 바이트(`hdfs dfs -du -h /tpcxai/sf<SF>`).
- 모델 라이브러리는 키트 버전(`/opt/kitenv`)으로 고정한다.

## 6. 알려진 위험

- **SF10 메모리**: SF1의 XGBoost 기울기 버퍼가 약 1.5GB였으므로 비례 추정 약 15GB. Docker 16GB에서 UC08 학습이 실패할 가능성이 크다.
  실패하면 `--workloads uc03`으로 전처리만 재거나, 실패 지점 자체를 한계 결과로 보고한다. SF3도 약 4.5GB라 한 번은 지켜본다.
- **speedup 상한**: UC08 학습은 Spark 밖 단일 프로세스이고 작업 시간의 63~73%다. 암달의 법칙상 전체 speedup 상한은 약 1.4~1.6배.
  전체 시간과 Spark 전처리 구간 시간을 따로 보고한다.
- **단일 호스트**: Mac 한 대 위의 Docker라 워커 간 통신이 실제 네트워크가 아니다. 한계로 명시한다.
- **디스크**: SF3는 HDFS 복제 2를 포함해 원본만 약 5GB(SF10은 약 17GB)에 Parquet 테이블이 더해진다. Docker 디스크 여유를 확인한다.

## 7. 분석과 산출물

결과 합치기: `python tools/compare_runs.py runs/*` → `runs/all_stages.csv`. 반복 3회의 평균 ± 표준편차로 보고한다.

1. 단계별 시간 분해(load, preprocess, train, predict, score), 묶음 A
2. separate vs shared 전처리 합계(`train/serve/score`의 `preprocess`), SF1과 SF3에서 결론이 바뀌는지
3. executor 1 → 2 speedup(전체 / Spark 전처리 구간), 로컬 기준선과 비교
4. SF1 → SF3 단계별 시간 증가 비율과 실제 입력 행 수·바이트 증가 비율(채점 데이터는 고정이라는 점 포함)
5. 최대 메모리, 셔플 바이트, 스필
6. 한계, M1·M2 계획 대비 변경점(키트 드라이버 대신 PDGF 값으로 SF 지정, 측정 방식 변경 등)

## 8. 일정

| 날짜 | VM (x86) | Mac (측정) |
| --- | --- | --- |
| 11/21 (토) | Java 8·키트 준비, SF1 md5 검증, SF3 생성 시작 | `git pull`, 빌드, SF1 재현, 묶음 A |
| 11/22 (일) | SF3 압축·전송, 밤에 SF10 생성 | 묶음 B, C |
| 11/23 (월) | | SF3 적재·워밍업, 묶음 D |
| 11/24 (화) | | SF10 1회 시도(선택), 실패한 실행 다시 하기 |
| 11/25 (수) | | 예비일 |
| **11/26 (목)** | | **측정 완료**, `compare_runs.py runs/*` |
| 11/27 ~ 12/2 | | 분석, 그래프, 보고서, 발표 자료 |
| 12/3 (목) | | 제출 |
