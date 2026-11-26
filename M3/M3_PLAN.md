# M3 계획 (Team7, TPCx-AI UC03 + UC08) — 인수인계본 (11/26)

M1·M2 보고서, 저장소 `M2/`(커밋 2239421)의 README·`run.py`·`docker/*.sh`, 1번 축 결과(성윤, 11/21, 브랜치 `m3-sy`)를 바탕으로 정리했다.
**제출 12/3(목).**

## 0. 현재 상태와 다음 할 일

| 항목 | 상태 |
| --- | --- |
| 데이터 생성 (VM) | **완료.** PDGF SF1(검증용)·SF3·SF9·SF10, 88개 검증 항목 통과, SF1은 M2 데이터와 md5 14/14 일치 → [datagen/README.md](datagen/README.md) |
| 데이터 전송 | Mac `M3/m3data/`에 압축본·sha256 복사 완료(gitignore). **압축 해제·확인은 아직** (5.0절) |
| 1번 축: 자원 확장 | **완료** (성윤, MacBook Air M5 16GB, SF1, 브랜치 `m3-sy`의 `M3/resource_scaling/`). 요약 1절, 참고할 것 10절 |
| 2번 축: 데이터 확장 | **이 문서의 측정 대상.** Mac에서 SF1·3·9·10 × separate/shared × 3회 (5절) |

Mac에서 처음 열었다면: **5.0 → 5.1 → 5.4 묶음 순서**로 진행한다.

**작업 위치 규칙 (11/26 결정)**: 코드는 `M2/`(수정하지 않음), **데이터와 실행 결과는 전부 `M3/`**.

| 무엇 | 호스트(Mac) | client 컨테이너 | git |
| --- | --- | --- | --- |
| 파이프라인 코드 | `M2/` | `/workspace` | 추적 |
| 2번 축 입력 데이터 | `M3/m3data/sf{1,3,9,10}/` | `/m3/m3data/sf<SF>` | 제외 |
| 2번 축 실행 결과 | `M3/runs/<run_id>/`, `M3/runs/*.log` | `/m3/runs` | 제외 |
| 보고서용 요약 | `M3/results/<run_id>/` | | 추적 |
| M2 SF1 데이터 | `M2/data/sf1/` (참고만, `M3/m3data/sf1`로 복사해 사용) | `/workspace/data/sf1` | 제외 |

`M3/` mount는 M2 compose 파일을 고치지 않고 override [docker/compose.m3.yml](docker/compose.m3.yml)로 추가한다(5.1절).

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
  3GiB로 올린 보충 실험(r10~r13)은 `m3-sy`의 `results/memory_followup/`.
- 원인 모를 UC08 학습 지연 배치(+90초)가 있어 전체 시간 편차가 큼 → **자원·규모 효과는 Spark 전처리 시간으로 해석**.
- 조건: 셔플 파티션 24 고정, 회차마다 실행 순서 교대, clean 테이블 재사용.

→ 2번 축의 질문: **데이터가 커지면 shared 효과가 측정 오차 밖으로 나오는가, 시간은 데이터에 비례하는가.**

## 2. 기계 역할

| 기계 | 역할 | 상태 |
| --- | --- | --- |
| Mac (Apple Silicon, M2 README의 측정 기계, Docker 16GB) | **2번 축 측정 전부** | M2와 같은 기계. arm64와 x86 결과는 섞어 비교하지 않는다 |
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
4. 최대 메모리: Spark executor·셔플·스필은 `<run>/spark-events/`(History Server), 모델 프로세스를 포함한 컨테이너 메모리는 Mac에서 `docker stats`를 기록한다.
5. M2를 고치지 않고 M3에서 데이터·결과를 다루는 방법:
   - compose는 `M2/`만 `/workspace`로 mount한다 → override [docker/compose.m3.yml](docker/compose.m3.yml)이 client에 `M3/`를 `/m3`로 추가.
   - `M2/docker/load_hdfs.sh`는 원본을 `/workspace/data/sf<SF>`로 고정 → [docker/m3_load.sh](docker/m3_load.sh)가 같은 명령으로 `/m3/m3data/sf<SF>`를 올린다.
     HDFS 경로(`/tpcxai/sf<SF>`)는 같아서 `run.py` 인자는 M2와 같다.
   - `run.py --runs-dir`(70행)로 결과를 `/m3/runs`에 쓴다. 측정 함수는 [docker/m3_env.sh](docker/m3_env.sh).
   - Derby 메타스토어(`metastore_db/`)는 `run.py`를 `/workspace`에서 실행하므로 M2 쪽에 그대로 생긴다.

## 5. 측정 (Mac)

### 5.0 데이터 풀기와 확인 (Mac 터미널)

`M3/m3data/`에는 공유 폴더에서 복사한 `sf{3,9,10}_data.tar.gz`, `*.sha256`, `gen_sf*.log`, `validation_report.txt`가 있다.

```bash
cd <저장소>/M3/m3data
shasum -a 256 -c sf3_data.tar.gz.sha256 sf9_data.tar.gz.sha256 sf10_data.tar.gz.sha256   # ① 3개 모두 OK
for SF in 3 9 10; do tar -xzf sf${SF}_data.tar.gz; done                                    # → m3data/sf3, sf9, sf10
for SF in 3 9 10; do (cd sf$SF && shasum -a 256 -c --quiet ../sf$SF.sha256 && echo "SF$SF 14/14 OK"); done   # ②
cp -R ../../M2/data/sf1 sf1                                                                # SF1: M2 데이터 복사 (원본은 그대로 둠)
ls sf1 sf3 sf9 sf10                                                                        # 각각 scoring serving training
```

- ①은 전송 중 손상, ②는 압축 해제까지 포함해 VM에서 만든 파일과 같은지 확인한다. 같은 sha256 파일이 `M3/datagen/records/`에도 있다.
- SF1 사본 확인은 5.1절에서 컨테이너의 `md5sum`으로 한다(macOS에는 `md5sum`이 없다).
- 다 확인되면 압축본은 지워도 된다(공유 폴더에 원본이 있다). 디스크: 풀린 CSV 약 9.7GB(SF1 0.9, SF3 1.6, SF9 2.8, SF10 4.4).
- **Docker 디스크**: HDFS 복제 2라 CSV만 SF3 약 3.2GB, SF9 약 5.6GB, SF10 약 8.8GB이고 Parquet 테이블이 더해진다. `docker system df`와 Docker Desktop 디스크 한도를 먼저 확인한다.
  모자라면 한 SF의 측정이 끝난 뒤 `hdfs dfs -rm -r -skipTrash /tpcxai/sf<SF>`로 원본 CSV를 지운다(clean 테이블은 Parquet로 남는다. 단, 다시 `--reingest`하려면 재적재해야 한다).

### 5.1 클러스터 준비와 SF1 적재

Docker Desktop 자원: 메모리 16GB(M2 README), CPU는 M2 측정 때와 같게 둔다. 바꿨다면 값을 기록한다.

```bash
cd <저장소>/M2
export COMPOSE_FILE=docker-compose.yml:../M3/docker/compose.m3.yml   # ★ 새 터미널마다. 빠뜨리면 /m3 가 없다
docker compose config | grep -B2 -A2 'target: /m3'                 # client 에 source: .../M3, target: /m3 가 보이면 됨
docker images | grep tpcxai-hadoop || docker compose build           # 이미지 없으면 빌드(약 15분)
docker compose up -d
docker compose exec client bash -c 'cd /m3/m3data/sf1 && md5sum -c --quiet /m3/datagen/records/sf1_reference.md5 && echo "SF1 14/14 OK"'
docker compose exec client bash -c 'command -v zstd || echo "zstd 없음"'   # 5.6절 executor 점검에 필요
docker compose exec client /m3/docker/m3_load.sh 1                   # → M3/runs/hdfs_sf1.txt 에 입력 크기 기록
```

SF1 재현 확인은 따로 `run_cluster.sh`를 돌리지 않고 묶음 A의 첫 실행 결과로 한다: 로그의 MSLE 4.01xx, accuracy 0.69xx(M2 `results/`와 같은 값).
값이 다르면 측정을 멈추고 원인부터 본다.

### 5.2 측정 함수 (client 컨테이너 안)

```bash
docker compose exec client bash          # Mac 터미널, M2/ 에서 (COMPOSE_FILE 설정된 상태)
source /m3/docker/m3_env.sh              # 컨테이너를 다시 열면 다시 source
```

| 함수 | 하는 일 |
| --- | --- |
| `m3warm <SF>` | `--reingest --workloads uc03`로 clean 테이블 적재만(`m3_sf<SF>_warmup`, 분석 제외) |
| `m3run <SF> <EX> <반복> <먼저 모드>` | yarn, executor EX × 3코어 4GB, driver 3GB, 파티션 24로 두 모드를 연속 실행. 이름 `m3_sf<SF>_yarn_e<EX>c3m4g_r<반복>_<mode>` |
| `m3local <SF> <반복> <먼저 모드>` | 선택 묶음 C (local[6], driver 8GB) |
| `m3check <run_id>` | `checks failed` 수와 executor 추가 수를 출력하고 `M3/runs/executor_check.csv`에 기록(실행마다 자동) |
| `m3history '<패턴>'` | `/m3/runs` 이벤트 로그로 Spark History Server, http://localhost:4040 |

- 실행이 실패하면(exit ≠ 0) 같은 회차의 다음 모드로 넘어가지 않는다. 같은 이름이 이미 있으면 실행하지 않는다.
- 실행 이름 형식은 1번 축(`m3_sf1_yarn_e2c2m2g_r1_separate`)과 같아서 `m3-sy`의 집계 스크립트를 SF 정규식만 바꿔 쓸 수 있다(10절).

### 5.3 메모리 기록 (Mac 터미널 하나 더, `M3/`에서 측정하는 동안 계속)

```bash
cd <저장소>/M3 && mkdir -p runs
while true; do docker stats --no-stream --format '{{.Name}},{{.MemUsage}},{{.CPUPerc}}' | sed "s/^/$(date +%s),/"; sleep 5; done >> runs/docker_stats.csv
```

### 5.4 묶음 (client 컨테이너 안, `source /m3/docker/m3_env.sh` 후)

| 묶음 | 명령 | 실행 수 | 예상 기계 시간 | 답하는 질문 |
| --- | --- | --- | --- | --- |
| A. SF1 기준선 | `m3warm 1` 후 `m3run 1 2 1 separate`, `m3run 1 2 2 shared`, `m3run 1 2 3 separate` | 6 | 약 35분 | 단계별 비용, 조건을 맞춘 separate vs shared, SF1 재현 |
| D3. SF3 | `m3_load.sh 3`, `m3warm 3` 후 `m3run 3 2 1 separate`, `m3run 3 2 2 shared`, `m3run 3 2 3 separate` | 6 | 약 1시간 | 1.73배에서의 증가 비율, shared |
| D9. SF9 | `m3_load.sh 9`, `m3warm 9` 후 `m3run 9 2 1 separate`, `m3run 9 2 2 shared`, `m3run 9 2 3 separate` | 6 | 약 2시간 | 3배(고객만 증가) |
| D10. SF10 | `m3_load.sh 10`, `m3warm 10` 후 **먼저 `m3run 10 2 1 separate` 1세트로 메모리 확인**, 괜찮으면 r2(shared 먼저), r3 | 6 | 약 3시간 | 4.74배(고객 + 기간), 메모리 한계 |
| (선택) B. executor 1개 | `m3run 1 1 1 separate` … | 6 | 약 45분 | 1번 축에서 측정됨. 시간이 남을 때만 |
| (선택) C. 로컬 | `m3local 1 1 separate` … | 6 | 약 1시간 | 1번 축에서 측정됨. 시간이 남을 때만 |

- `m3_load.sh`는 컨테이너 안에서는 `/m3/docker/m3_load.sh <SF>`, Mac에서는 `docker compose exec client /m3/docker/m3_load.sh <SF>`.
- 예상 시간은 M2 SF1 실측에 행 배율을 곱한 추정이다. 적재·워밍업은 별도로 SF당 10~20분.
- 한 회차(`m3run`)가 끝날 때마다 `m3check` 줄을 확인한다: `checks failed: 0`, `executors_added=2`.
- SF10이 메모리로 실패하면 실패 지점(단계, `docker stats`, 오류)을 한계 결과로 기록하고 SF9를 상한으로 보고한다.

### 5.5 워밍업 (적재만, 결과는 분석에서 제외)

`m3warm <SF>` = 아래 명령. SF마다 `m3_load.sh <SF>` 뒤에 한 번.

```bash
python3 run.py --data-dir hdfs://namenode:9000/tpcxai/sf3 --sf 3 --master yarn --executors 2 --executor-cores 3 --executor-memory 4g \
  --driver-memory 3g --shuffle-partitions 24 --model-python /opt/kitenv/bin/python --mode separate --reingest --workloads uc03 \
  --run-id m3_sf3_warmup --runs-dir /m3/runs
```

### 5.6 executor 교체 점검 (1번 축에서 발견, 실행마다)

executor 2개 설정에서 추가된 executor가 2개보다 많으면 교체가 일어난 것이다. 그 실행은 성능 평균에서 빼고 안정성 결과로 따로 보고한다.

- `m3check`가 실행마다 자동으로 센다. 이벤트 로그는 1번 축에서 `.zstd`로 압축돼 있었다.
  컨테이너에 `zstd`가 없으면 `executors_added=?`로 나오니 Mac에서 `brew install zstd` 후 센다:
  `for d in runs/m3_sf*_r*_*/; do echo "$d $(zstd -dc $d/spark-events/* | grep -c SparkListenerExecutorAdded)"; done` (`M3/`에서)
- 또는 `m3history 'm3_sf10_*'`의 Executors 탭.
- 1번 축의 판정 방법: `m3-sy`의 `scripts/16_event_metrics.py`(이벤트 로그 집계), 판정 기록은 `results/spark_event_summary.csv`의 `timing_eligible` 열.

### 5.7 측정 규칙

- Mac 한 대에서, 전원 연결, 다른 프로그램 종료, 한 번에 하나씩(Derby 메타스토어 제약).
- 같은 이름으로 다시 돌리지 않는다. 실패한 실행은 반복 번호를 바꿔(예: `r4`) 다시 돌린다.
- 기록: `M3/runs/`의 `stages.csv`, `metrics.json`(행 수), `spark-events/`, `<run_id>.log`, `docker_stats.csv`, `executor_check.csv`, `hdfs_sf<SF>.txt`(입력 바이트).
- 모델 라이브러리는 키트 버전(`/opt/kitenv`)으로 고정한다.
- 보고서에 쓰는 실행은 `metrics.json`, `stages.csv`, `validation.json`을 `M3/results/<run_id>/`로 복사한다(`M3/.gitignore`가 `results/`의 CSV는 허용).

## 6. 알려진 위험

- **UC08 메모리**: SF1 XGBoost 기울기 버퍼가 약 1.5GB였고 학습 행 수에 비례한다고 보면 SF3 약 2.6GB, SF9 약 4.5GB, **SF10 약 7GB**(SF30이면 약 12GB).
  Spark 종료 후 별도 프로세스라 Docker 16GB에서 SF10까지는 가능할 것으로 보지만, 1세트로 먼저 확인한다.
- **shared의 메모리 압박**: 1번 축에서 작은 executor(2GiB)의 shared가 executor 교체를 겪었다. 우리 구성(4GB/3코어, 태스크당 약 1.33GB)도 SF10 shared에서 생길 수 있다(5.6절로 점검).
- **speedup·확장 해석**: UC08 학습이 작업 시간의 60~75%다. 데이터 확장 비율과 shared 효과는 **Spark 전처리 시간**으로 판단하고 전체 시간은 함께 보고만 한다.
- **SF10의 두 가지 변화**: 고객과 학습 기간이 동시에 늘고 scoring 날짜도 옮겨진다. SF1→3→9(고객만)와 구분해 해석한다.
- **단일 호스트**: Mac 한 대 위의 Docker라 워커 간 통신이 실제 네트워크가 아니다.
- **`COMPOSE_FILE` 누락**: 설정 없이 `docker compose up`을 하면 client에 `/m3`가 없다. `m3_load.sh`가 `/m3/...` 없음으로 멈추면 5.1절 export부터 다시 한다(`up -d`로 client가 다시 만들어진다).
- **디스크**: 5.0절.

## 7. 분석과 산출물

결과 합치기(client 컨테이너 안): `python3 tools/compare_runs.py /m3/runs/m3_sf*_r*_*/` → `M3/runs/all_stages.csv`.
반복 3회의 평균 ± 표본 표준편차(교체 실행 제외)로 보고한다.

1. 단계별 시간 분해(load, preprocess, train, predict, score), SF1 기준
2. **separate vs shared 전처리 합계**(`train/serve/score`의 `preprocess`)를 SF1·3·9·10에서 비교. 차이가 표준편차의 몇 배인지 함께 적는다
3. SF1 대비 단계별 시간 배율과 실제 입력 행 수·바이트 배율(1.73, 3.00, 4.74). 채점 단계는 고정 크기
4. UC08 학습 시간 배율과 메모리, SF10 성공 여부
5. 셔플 바이트, 스필, 피크 메모리, executor 교체 여부 → `m3-sy`의 `16_event_metrics.py`로 1번 축과 같은 열로 뽑는다(10절)
6. 1번 축과 배율 비교(기계가 달라 절대 시간은 비교하지 않음)
7. 한계, M1·M2 계획 대비 변경점(PDGF `-sf` 값 사용과 √SF 규칙, SF9 추가, 측정 방식 변경 등)

## 8. 일정 (11/26 재조정)

| 날짜 | Mac (측정) |
| --- | --- |
| 11/26 (목) | 5.0 데이터 풀기·확인, 5.1 클러스터·SF1 적재, 묶음 A, SF3 적재·워밍업 |
| 11/27 (금) | 묶음 D3, SF9 적재·워밍업, 묶음 D9 |
| 11/28 (토) | SF10 적재·워밍업, D10 1세트 확인 후 반복, **측정 완료**, `compare_runs.py` |
| 11/29 ~ 12/2 | 분석, 그래프, 보고서, 발표 자료 (1번 축 결과와 합치기) |
| 12/3 (목) | 제출 |

## 9. 바뀐 것

11/21 계획 대비:

- 데이터: SF3·SF10 → **SF3·SF9·SF10** 생성 완료. "SF3 = 3배"는 틀린 추정이었다(실제 1.73배, √SF 규칙).
- 생성 스크립트: VM 홈 폴더의 임시 스크립트 대신 저장소 `M3/datagen/gen_sf.sh`(M2 README 블록 그대로)로 하고 기록을 남겼다.
- 측정 범위: 1번 축(자원·로컬)이 따로 완료되어 Mac 측정은 **2번 축(A + D3·D9·D10)** 중심으로 하고, B·C는 선택으로 내렸다.
- 측정 조건: `--shuffle-partitions 24` 명시, executor 교체 점검 추가, 주 지표를 Spark 전처리 시간으로.
- 메모리 추정: SF10 약 15GB → 약 7GB(행 배율 4.74 기준).

11/24 인수인계본 대비 (11/26):

- 데이터·실행 결과 위치: `M2/data`, `M2/runs` → **`M3/m3data`, `M3/runs`**. M2 파일은 고치지 않고 `M3/docker/`(compose override, `m3_load.sh`, `m3_env.sh`)로 처리.
- SF1 재현: `run_cluster.sh` 별도 실행 대신 묶음 A 첫 실행의 점수로 확인.
- 실행 이름: `sf<SF>_yarn_e2c3_r<n>_kit_<mode>` → 1번 축과 같은 형식 `m3_sf<SF>_yarn_e2c3m4g_r<n>_<mode>`.
- 일정: 측정 완료 11/26 → 11/28.

## 10. 1번 축 브랜치(`m3-sy`)에서 참고할 것 (merge하지 않음)

`m3-sy`(커밋 `c544f2e`)는 `M3/resource_scaling/`에 새 파일 188개만 더했고 M2는 바꾸지 않았다. m3-mj와 겹치는 파일이 없어 충돌은 없지만,
결과 파일이 많아 m3-mj에 merge하지 않고 각자 main으로 PR한다. 볼 때는 `git fetch origin` 후 `git show origin/m3-sy:<경로>`.

| 파일 (`M3/resource_scaling/`) | 내용 | 2번 축에서 |
| --- | --- | --- |
| `scripts/m3_resource.sh` | 1번 축 측정 함수. 회차별 순서 교대(홀수 separate 먼저), 파티션 24, `--reingest` 없음, `COOLDOWN`(실행 전 대기), `MODES` | `m3_env.sh`가 같은 규칙을 따른다. 발열이 의심되면 `COOLDOWN` 방식 참고 |
| `scripts/16_event_metrics.py` | 이벤트 로그 → M1 표 5 지표(워커별 시간, CPU, 원격 셔플 바이트, 스필, 피크 메모리, GC), `validation.json` 요약 | 7절 5번에 그대로 쓴다. 실행 이름 정규식이 `m3_sf1_...`로 고정이라 `m3_sf\d+_...`로만 바꾼다. `zstd` 필요 |
| `scripts/08_summarize.py`, `09_plot.py`, `11_report_table.py` | 설정별 평균·표준편차, speedup 그래프, 보고서 표 | 보고서 그래프·표 형식을 맞출 때 |
| `DECISIONS.md` | 1번 축 설계 결정(설정 선택, 제외 규칙, 측정 순서) | 보고서에서 두 축의 방법을 같은 말로 설명할 때 |
| `results/memory_followup/README.md` | executor 2GiB → 3GiB 보충 실험: 교체가 메모리 때문이었는지 | SF10 shared에서 교체가 나면 같은 방식으로 해석 |
| `results/spark_event_summary.csv` | 실행별 `timing_eligible`(교체 실행 제외 판정) | 5.6절 판정 기준을 맞춘다 |
| `scripts/01_setup.sh` | 별도 작업 폴더 `~/m3work`에 clone해 M2를 `2239421`로 checkout | **같은 Mac에서 돌리면** `~/m3work/.../M2` 컨테이너와 이름(`tpcxai`)이 겹친다. 측정 전 `docker ps`로 확인 |

- 1번 축 측정 M2 코드 = `2239421`. m3-mj의 M2도 같다(`M2/.gitignore` 3줄만 다름) → 두 축의 파이프라인 코드는 같다.
