# M3 계획 (Team7, TPCx-AI UC03 + UC08) — 인수인계본 (11/24)

M1·M2 보고서, 저장소 `M2/`(커밋 2239421)의 README·`run.py`·`docker/*.sh`, 1번 축 결과(성윤, 11/21)를 바탕으로 정리했다.
**측정 완료 11/26(목), 제출 12/3(목).**

## 0. 현재 상태와 다음 할 일

| 항목 | 상태 |
| --- | --- |
| 데이터 생성 (VM) | **완료.** PDGF SF1(검증용)·SF3·SF9·SF10, 88개 검증 항목 통과, SF1은 M2 데이터와 md5 14/14 일치 → [datagen/README.md](datagen/README.md) |
| 데이터 전송 | 공유 폴더 `Works/26-2-Yonsei/m3data/`에 압축본과 sha256. **Mac에서 받기·확인은 아직** (5.0절) |
| 1번 축: 자원 확장 | **완료** (성윤, MacBook Air M5 16GB, SF1). 결과 PDF `M3_자원확장_결과.pdf`(팀 공유, 저장소에는 넣지 않음). 요약은 1절 |
| 2번 축: 데이터 확장 | **이 문서의 측정 대상.** Mac에서 SF1·3·9·10 × separate/shared × 3회 (5절) |

Mac에서 처음 열었다면: **5.0 → 5.1 → 5.4 묶음 순서**로 진행한다.

## 1. 목표

- 수업 요구사항: Milestone 3 = "Performance Analysis w/ Scalability Test" (보고서 + 5분 발표).
- 팀의 질문(M1부터): UC03과 UC08이 같은 조인(Order ⋈ Lineitem ⋈ Product)을 쓰는데, 각자 조인(separate)과
  한 번 조인해 저장 후 공유(shared) 중 어느 쪽이 나은가, 그 답이 규모에 따라 바뀌는가.
- M1 표 5의 세 비교: 단계별 비용, 데이터 증가(**2번 축**), 자원 증가(**1번 축**).
- M2 결과(SF1, executor 2 × 3코어 4GB, 각 1회): 작업 시간 separate 292초, shared 354초, MSLE 4.01, accuracy 0.693.
  shared만 `--reingest`로 적재부터 하고 먼저 실행해서 조건이 같지 않았다.

### 1번 축 결과 요약 (2번 축 설계에 반영한 것)

- Spark 전처리는 자원을 늘리면 1.6~2.0배 빨라지고 4코어 이후 둔화. 오차 범위가 겹치지 않아 **유의미**.
- UC08 학습(XGBoost)은 자원과 무관하게 약 260~290초 → 전체 향상 상한 1.18배(암달). **유의미**.
- shared 효과: 전처리 66.4 → 63.2초(3초, 표준편차의 약 1.4배, n=3) → **유의미하지 않음**. 전체 시간은 같음.
- 작은 executor(1개 × 2GB)에서 shared 3회 중 2회 executor 교체(SIGTERM, 메모리 압박) → 성능 평균에서 제외하고 따로 보고.
- 원인 모를 UC08 학습 지연 배치(+90초)가 있어 전체 시간 편차가 큼 → **자원·규모 효과는 Spark 전처리 시간으로 해석**.
- 조건: 셔플 파티션 24 고정, 회차마다 실행 순서 교대, clean 테이블 재사용.

→ 2번 축의 질문: **데이터가 커지면 shared 효과가 측정 오차 밖으로 나오는가, 시간은 데이터에 비례하는가.**

## 2. 기계 역할

| 기계 | 역할 | 상태 |
| --- | --- | --- |
| Mac (M4 Pro 24GB, Docker 16GB) | **2번 축 측정 전부** | M2와 같은 기계. arm64와 x86 결과는 섞어 비교하지 않는다 |
| x86 Ubuntu VM (VMware, 4 vCPU, 7.2GiB) | 데이터 생성 전용 | 완료. 원본은 `~/Works_ub/m3data/data/`에 Mac 확인 전까지 보관 |
| MacBook Air M5 16GB (성윤) | 1번 축 측정 | 완료 |

기계가 서로 다르므로 1번 축과 2번 축은 **절대 시간을 비교하지 않고, 각 축 SF1 기준 대비 배율만** 나란히 놓는다.

## 3. 데이터 (완료)

자세한 내용과 근거는 [datagen/README.md](datagen/README.md).

- 생성: [datagen/gen_sf.sh](datagen/gen_sf.sh) = M2 README 3절 PDGF 명령 블록 그대로(Java 8 직접 실행, 키트 드라이버와 같은 시드·옵션).
  키트 드라이버의 `-sf`(GB 단위)는 쓰지 않는다. M2 SF1과 비교하려고 PDGF `-sf` 값을 그대로 준다.
- **SF와 데이터 크기는 비례하지 않는다**(스키마: 고객 ∝ √SF, 주 수는 SF10부터 156주).

| PDGF SF | 학습 주문 | SF1 대비 | 학습 기간 | 늘어나는 것 |
| --- | --- | --- | --- | --- |
| 1 | 5,200,000 | 1 | 2년 | 기준 |
| 3 | 9,006,664 | 1.73 | 2년 | 고객 |
| 9 | 15,600,000 | 3.00 | 2년 | 고객 |
| 10 | 24,665,765 | 4.74 | **3년** | 고객 + 기간 (serving·scoring 날짜도 1년 뒤로) |

- **채점(scoring)은 모든 SF에서 order 520,000건으로 고정**이다(킷 규칙). 데이터 확장 분석은 train·serve 단계로 하고, score 단계 시간이 거의 같은 이유를 보고서에 적는다.
- SF9를 추가한 이유: (1) SF1→3→9가 기간을 고정하고 고객만 늘리는 계열(1, 1.73, 3배)이 된다.
  (2) SF10이 메모리로 실패하면 SF9를 대체 상한으로 쓴다.
- SF30 이상은 만들지 않는다. shared 비교에는 UC03과 UC08이 둘 다 돌아야 하는데(`--workloads uc03`만으로는 공유할 상대가 없다)
  UC08 XGBoost 메모리가 행 수에 비례해 Docker 16GB를 넘는다(6절).

## 4. 코드 확인 결과 (측정 방법에 영향)

1. `run_cluster.sh`는 항상 **shared를 `--reingest`로 먼저**, separate를 그다음에 돌린다. M2의 조건 불일치가 여기서 나왔다.
   → 반복 측정은 `run.py`를 직접 호출해 **두 모드 모두 `--reingest` 없이**(clean 테이블 재사용, load 0초) 돌리고, 반복마다 순서를 바꾼다.
   shared의 조인 저장은 load가 아니라 preprocess에 들어가므로, 이 조건이 공정한 비교다.
2. clean 테이블은 SF 라벨별 Hive DB(`sf1_clean`, `sf3_clean`, …)에 생긴다. SF마다 한 번 적재(워밍업)한 뒤 측정한다.
   워밍업을 `--workloads uc03`으로 돌려도 적재는 세 split 모두 한다(`run.py` 146~151행, `SPLIT_TABLES`).
3. 셔플 파티션 기본값은 `총 코어 × 4`(`src/common/spark.py` 18행)라 executor 2 × 3코어면 24다.
   1번 축과 맞추고 SF가 바뀌어도 고정되도록 **`--shuffle-partitions 24`를 명시**한다. 파티션 수가 고정이라 SF가 커지면 파티션이 커지고 스필이 늘 수 있는데, 이것도 결과로 기록한다.
4. 최대 메모리: Spark executor·셔플·스필은 `runs/<id>/spark-events/`(History Server `docker/history_server.sh`), 모델 프로세스를 포함한 컨테이너 메모리는 Mac에서 `docker stats`를 기록한다.

## 5. 측정 (Mac)

### 5.0 데이터 받기와 확인

공유 폴더 `Works/26-2-Yonsei/m3data/`(저장소 밖)에서. 경로는 Mac에 맞게 바꾼다.

```bash
D=<Works>/26-2-Yonsei/m3data
REPO=<Works>/26-2-Yonsei/yonsei-tpcx-ai-sales-forecasting
cd "$D" && shasum -a 256 -c sf3_data.tar.gz.sha256 sf9_data.tar.gz.sha256 sf10_data.tar.gz.sha256   # ① 3개 모두 OK

for SF in 3 9 10; do tar -xzf "$D/sf${SF}_data.tar.gz" -C "$REPO/M2/data/"; done                   # → M2/data/sf3, sf9, sf10

for SF in 3 9 10; do (cd "$REPO/M2/data/sf$SF" && shasum -a 256 -c --quiet "$D/sf$SF.sha256" && echo "SF$SF 14/14 OK"); done   # ②
```

- ①은 전송 중 손상, ②는 압축 해제까지 포함해 VM에서 만든 파일과 같은지 확인한다. 저장소의 `M3/datagen/records/`에도 같은 sha256 파일이 있다.
- `M2/data/`는 gitignore 대상이다. SF1은 기존 `M2/data/sf1`을 그대로 쓴다.
- **Docker 디스크**: HDFS 복제 2라 CSV만 SF3 약 3.2GB, SF9 약 5.6GB, SF10 약 8.8GB이고 Parquet 테이블이 더해진다. `docker system df`와 Docker Desktop 디스크 한도를 먼저 확인한다.
  모자라면 한 SF의 측정이 끝난 뒤 `hdfs dfs -rm -r -skipTrash /tpcxai/sf<SF>`로 원본 CSV를 지운다(clean 테이블은 Parquet로 남는다. 단, 다시 `--reingest`하려면 재적재해야 한다).

### 5.1 준비와 SF1 재현 (이미 했으면 건너뛴다)

```bash
cd M2
docker compose build && docker compose up -d
docker compose exec client docker/load_hdfs.sh 1
docker compose exec client docker/run_cluster.sh 1 2 3 4g    # 약 12분. clean 테이블 적재(워밍업)도 겸한다
```

MSLE 4.01, accuracy 0.693이면 환경이 맞다(`results/`의 같은 이름 폴더와 비교). 이 두 실행은 재현 확인용이고 분석에는 넣지 않는다.

### 5.2 측정 함수 (client 컨테이너 안: `docker compose exec client bash`)

```bash
KIT=/opt/kitenv/bin/python
m3run() {   # m3run <SF> <executors> <반복> <먼저 돌릴 모드>
  SF=$1; EX=$2; REP=$3; FIRST=$4
  C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master yarn --executors $EX --executor-cores 3 --executor-memory 4g --driver-memory 3g --shuffle-partitions 24 --model-python $KIT"
  TAG="sf${SF}_yarn_e${EX}c3_r${REP}"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do python3 run.py $C --mode $M --run-id "${TAG}_kit_$M" 2>&1 | tee "runs/${TAG}_kit_$M.log"; done
}
m3local() { # m3local <SF> <반복> <먼저 돌릴 모드>   (선택 묶음 C용)
  SF=$1; REP=$2; FIRST=$3
  C="--data-dir hdfs://namenode:9000/tpcxai/sf$SF --sf $SF --master local --workers 6 --driver-memory 8g --shuffle-partitions 24 --model-python $KIT"
  TAG="sf${SF}_local6_r${REP}"
  [ "$FIRST" = shared ] && ORDER="shared separate" || ORDER="separate shared"
  for M in $ORDER; do python3 run.py $C --mode $M --run-id "${TAG}_kit_$M" 2>&1 | tee "runs/${TAG}_kit_$M.log"; done
}
```

컨테이너를 다시 열면 함수가 사라지므로 다시 붙여 넣는다.

### 5.3 메모리 기록 (Mac 터미널, `M2/`에서 측정하는 동안 계속)

```bash
while true; do docker stats --no-stream --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' | sed "s/^/$(date +%s),/"; sleep 5; done >> runs/docker_stats.csv
```

### 5.4 묶음

| 묶음 | 명령 | 실행 수 | 예상 기계 시간 | 답하는 질문 |
| --- | --- | --- | --- | --- |
| A. SF1 기준선 | `m3run 1 2 1 separate`, `m3run 1 2 2 shared`, `m3run 1 2 3 separate` | 6 | 약 35분 | 단계별 비용, 조건을 맞춘 separate vs shared |
| D3. SF3 | 워밍업 후 `m3run 3 2 1 separate`, `m3run 3 2 2 shared`, `m3run 3 2 3 separate` | 6 | 약 1시간 | 1.73배에서의 증가 비율, shared |
| D9. SF9 | 워밍업 후 `m3run 9 2 1 separate`, `m3run 9 2 2 shared`, `m3run 9 2 3 separate` | 6 | 약 2시간 | 3배(고객만 증가) |
| D10. SF10 | 워밍업 후 **먼저 `m3run 10 2 1 separate` 1세트로 메모리 확인**, 괜찮으면 r2(shared 먼저), r3 | 6 | 약 3시간 | 4.74배(고객 + 기간), 메모리 한계 |
| (선택) B. executor 1개 | `m3run 1 1 1 separate` … | 6 | 약 45분 | 1번 축에서 측정됨. 시간이 남을 때만 |
| (선택) C. 로컬 | `m3local 1 1 separate` … | 6 | 약 1시간 | 1번 축에서 측정됨. 시간이 남을 때만 |

- 예상 시간은 M2 SF1 실측에 행 배율을 곱한 추정이다. 워밍업(적재)은 별도로 SF당 10~20분.
- SF10이 메모리로 실패하면 실패 지점(단계, `docker stats`, 오류)을 한계 결과로 기록하고 SF9를 상한으로 보고한다.

### 5.5 워밍업 (적재만, 결과는 분석에서 제외)

```bash
docker compose exec client docker/load_hdfs.sh 3        # 9, 10도 같은 방식
# client 컨테이너 안
python3 run.py --data-dir hdfs://namenode:9000/tpcxai/sf3 --sf 3 --master yarn --executors 2 --executor-cores 3 --executor-memory 4g \
  --driver-memory 3g --shuffle-partitions 24 --model-python /opt/kitenv/bin/python --mode separate --reingest --workloads uc03 --run-id sf3_warmup
```

### 5.6 executor 교체 점검 (1번 축에서 발견, 실행마다)

executor 2개 설정에서 추가된 executor가 2개보다 많으면 교체가 일어난 것이다. 그 실행은 성능 평균에서 빼고 안정성 결과로 따로 보고한다.

```bash
# M2/ 에서. 이벤트 로그가 압축(.zstd/.lz4)돼 있으면 History Server(docker/history_server.sh)의 Executors 탭에서 확인
for d in runs/sf*_r*_kit_*/; do echo "$d executors_added=$(cat $d/spark-events/* 2>/dev/null | grep -c '"Event":"SparkListenerExecutorAdded"')"; done
```

1번 축에서 같은 판정을 한 방법이 있으면 성윤에게 받아 맞춘다.

### 5.7 측정 규칙

- Mac 한 대에서, 전원 연결, 다른 프로그램 종료, 한 번에 하나씩(Derby 메타스토어 제약).
- 같은 이름으로 다시 돌리면 `already exists`로 멈춘다. 실패한 실행은 반복 번호를 바꿔(예: `r4`) 다시 돌린다.
- 기록: `stages.csv`, `metrics.json`(행 수), `spark-events/`, `runs/docker_stats.csv`, 입력 바이트(`hdfs dfs -du -h /tpcxai/sf<SF>`).
- 모델 라이브러리는 키트 버전(`/opt/kitenv`)으로 고정한다.
- 보고서에 쓰는 실행은 `metrics.json`, `stages.csv`, `validation.json`을 `M3/results/<run_id>/`로 복사한다.

## 6. 알려진 위험

- **UC08 메모리**: SF1 XGBoost 기울기 버퍼가 약 1.5GB였고 학습 행 수에 비례한다고 보면 SF3 약 2.6GB, SF9 약 4.5GB, **SF10 약 7GB**(SF30이면 약 12GB).
  Spark 종료 후 별도 프로세스라 Docker 16GB에서 SF10까지는 가능할 것으로 보지만, 1세트로 먼저 확인한다.
- **shared의 메모리 압박**: 1번 축에서 작은 executor의 shared가 executor 교체를 겪었다. 우리 구성(4GB/3코어, 태스크당 약 1.33GB)도 SF10 shared에서 생길 수 있다(5.6절로 점검).
- **speedup·확장 해석**: UC08 학습이 작업 시간의 60~75%다. 데이터 확장 비율과 shared 효과는 **Spark 전처리 시간**으로 판단하고 전체 시간은 함께 보고만 한다.
- **SF10의 두 가지 변화**: 고객과 학습 기간이 동시에 늘고 scoring 날짜도 옮겨진다. SF1→3→9(고객만)와 구분해 해석한다.
- **단일 호스트**: Mac 한 대 위의 Docker라 워커 간 통신이 실제 네트워크가 아니다.
- **디스크**: 5.0절.

## 7. 분석과 산출물

결과 합치기: `python tools/compare_runs.py runs/*` → `runs/all_stages.csv`. 반복 3회의 평균 ± 표본 표준편차(교체 실행 제외)로 보고한다.

1. 단계별 시간 분해(load, preprocess, train, predict, score), SF1 기준
2. **separate vs shared 전처리 합계**(`train/serve/score`의 `preprocess`)를 SF1·3·9·10에서 비교. 차이가 표준편차의 몇 배인지 함께 적는다
3. SF1 대비 단계별 시간 배율과 실제 입력 행 수·바이트 배율(1.73, 3.00, 4.74). 채점 단계는 고정 크기
4. UC08 학습 시간 배율과 메모리, SF10 성공 여부
5. 셔플 바이트, 스필, executor 교체 여부
6. 1번 축과 배율 비교(기계가 달라 절대 시간은 비교하지 않음)
7. 한계, M1·M2 계획 대비 변경점(PDGF `-sf` 값 사용과 √SF 규칙, SF9 추가, 측정 방식 변경 등)

## 8. 일정

| 날짜 | Mac (측정) |
| --- | --- |
| 11/24 (화) | 5.0 데이터 받기·확인, 5.1 빌드·SF1 재현(안 했으면), 묶음 A, SF3 적재·워밍업 |
| 11/25 (수) | 묶음 D3, SF9 적재·워밍업, 묶음 D9 |
| 11/26 (목) | SF10 적재·워밍업, D10 1세트 확인 후 반복, **측정 완료**, `compare_runs.py runs/*` |
| 11/27 ~ 12/2 | 분석, 그래프, 보고서, 발표 자료 (1번 축 결과와 합치기) |
| 12/3 (목) | 제출 |

## 9. 11/21 계획에서 바뀐 것

- 데이터: SF3·SF10 → **SF3·SF9·SF10** 생성 완료. "SF3 = 3배"는 틀린 추정이었다(실제 1.73배, √SF 규칙).
- 생성 스크립트: VM 홈 폴더의 임시 스크립트 대신 저장소 `M3/datagen/gen_sf.sh`(M2 README 블록 그대로)로 하고 기록을 남겼다.
- 측정 범위: 1번 축(자원·로컬)이 따로 완료되어 Mac 측정은 **2번 축(A + D3·D9·D10)** 중심으로 하고, B·C는 선택으로 내렸다.
- 측정 조건: `--shuffle-partitions 24` 명시, executor 교체 점검 추가, 주 지표를 Spark 전처리 시간으로.
- 메모리 추정: SF10 약 15GB → 약 7GB(행 배율 4.74 기준).
