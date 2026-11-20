# M3 계획 (Team7, TPCx-AI UC03 + UC08)

이 파일은 M3 작업의 인수인계 문서다. 다른 Claude 세션에서 M1 보고서, M2 보고서, M2 README를 읽고 정리한 결론이며,
이 저장소의 코드(`run.py`, `docker/run_cluster.sh` 등)는 그 세션에서 **읽지 못했다**. 아래 "먼저 확인할 것"부터 처리한다.

## 배경

- 수업 요구사항: Milestone 3 = "Performance Analysis w/ Scalability Test" (보고서 + 5분 발표). 마감 12/3(목).
- 팀의 질문(M1부터): UC03과 UC08이 같은 조인(Order ⋈ Lineitem ⋈ Product)을 쓰는데,
  각자 조인(separate)과 한 번 조인해 저장 후 공유(shared) 중 어느 쪽이 나은가, 그 답이 규모에 따라 바뀌는가.
- M2 결과(SF1, executor 2 × 3코어 4GB, 키트 버전 모델, 각 1회): 작업 시간 separate 292초, shared 354초.
  MSLE 4.01, accuracy 0.693. 단, shared만 적재부터 새로 하고 먼저 실행해서 조건이 같지 않았다.
- 현재 상태: 저장소 clone 완료, `sf1_data.tar.gz` 압축 해제 완료(`M2/data/sf1/`). 아직 실행은 안 해 봄.

## 데이터 생성에 대한 결정

- SF3·SF10 생성은 과제 요구사항이 아니라 팀 계획이다. M1 6절은 "자원이 허락하면" 확장한다고 적었다.
- PDGF는 Apple Silicon에서 멈추므로 x86 Linux + Java 8이 필요하다. M2 담당자에게 SF3 생성을 요청한다.
- **기한 규칙**: 11/19(목)까지 SF3가 없으면 SF1을 25%·50%·100%로 샘플링한 데이터 확장으로 대체한다.

## 측정 계획

기본 설정: executor 2개 × 3코어 4GB, 키트 버전 모델(`/opt/kitenv`). 모든 조건을 separate·shared 두 모드로 각 3회.

| 묶음 | 조건 | 실행 수 | 답하는 질문 |
| --- | --- | --- | --- |
| A. SF1 기준선 | SF1, executor 2 | 6 | 단계별 비용, 조건을 맞춘 separate vs shared |
| B. 자원 확장 | SF1, executor 1 | 6 | executor 증가에 따른 speedup |
| C. 로컬 기준선 | SF1, `--master local` | 6 | 클러스터 vs 단일 프로세스 |
| D. 데이터 확장 | SF3, executor 2 (또는 샘플링 대체) | 6 | 시간이 데이터에 비례하는가, shared가 유리해지는가 |
| (선택) SF10 | 1회 시도 | 1~2 | 메모리 한계 지점 |

측정 규칙

- 같은 기계 한 대에서, 전원 연결, 다른 프로그램 종료, 한 번에 하나씩(Derby 메타스토어 제약).
- 두 모드의 적재 조건을 같게(둘 다 clean 테이블 재사용), 실행 순서는 번갈아.
- 반복 실행은 `docker/run_cluster.sh <SF> <executors> <cores> <memory> <반복 번호>`.
- 기록: 단계별 시간(`stages.csv`), 입력 행 수·바이트, 셔플 바이트·스필·최대 메모리(`spark-events/`, History Server).
- 플랫폼을 섞어 비교하지 않는다(arm64 MSLE 4.01, x86 3.95).

## 먼저 확인할 것 (코드를 읽고 답할 것)

1. `docker/run_cluster.sh`가 두 모드를 어떤 순서로 돌리는지, 적재(`--reingest`) 조건을 어떻게 다루는지.
   두 모드의 조건을 맞추려면 스크립트 수정이나 직접 `run.py` 호출이 필요한지.
2. 로컬 모드(묶음 C)를 client 컨테이너 안에서 키트 버전 모델로 돌리는 명령.
3. executor 1개 실행(묶음 B)이 `run_cluster.sh 1 1 3 4g`로 되는지. 워커당 YARN 6GB·4 vcore 한도 확인.
4. SF1 샘플링 데이터를 만들 방법(주문 ID 기준으로 order·lineitem을 함께 자르기)과 `--sf` 라벨 지정.
5. 최대 메모리를 어디서 얻을지(이벤트 로그, `docker stats`, 모델 프로세스).

### 확인 결과 (11/17, 코드 확인)

1. `run_cluster.sh`는 shared를 `--reingest`로 먼저, separate를 clean 테이블 재사용으로 나중에 돌린다(순서·적재 고정).
   조건을 맞추려면 스크립트에 "적재 생략 + 순서 지정" 옵션을 추가하거나 `run.py`를 직접 호출한다.
   SF1 재현만은 M2와 같게 원래 스크립트로 한다.
2. client 컨테이너에는 `TPCXAI_MASTER=yarn`, HDFS warehouse가 환경변수로 들어 있어 `--warehouse`를 따로 줘야 한다.
   로컬 모드는 Derby 메타스토어가 클러스터와 따로라(`metastore_db/` vs `metastore_cluster/`) 첫 실행은 다시 적재한다.
   ```bash
   docker compose exec client python3 run.py --master local --warehouse /workspace/warehouse \
     --data-dir /workspace/data/sf1 --sf 1 --workers 6 --driver-memory 8g \
     --model-python /opt/kitenv/bin/python --mode shared --run-id sf1_local_w6_kit_shared
   ```
3. `run_cluster.sh 1 1 3 4g`로 된다(executor 4GB + overhead → 4.5GB, AM 약 1GB 포함 6GB 이하, 3코어 ≤ 4 vcore).
   단, shuffle partition이 `코어 × 4`로 자동 결정되어 executor 1개 = 12, 2개 = 24로 같이 바뀐다.
   speedup만 보려면 `--shuffle-partitions 24`로 고정해야 하는데 스크립트에 옵션이 없다.
4. 샘플링 도구는 없어서 새로 만든다. 주문 ID(`o_order_id % 4` 등)로 order·lineitem·order_labels를 함께 자르고
   product·store_dept·store_dept_labels는 그대로 복사한다. `data/<라벨>/`에 두면 `load_hdfs.sh <라벨>`, `run_cluster.sh <라벨>`이
   그대로 쓴다. 실제 PDGF SF와 헷갈리지 않게 라벨은 `1p25`, `1p50` 형식.
5. 이벤트 로그에는 지금 태스크 단위 값(Peak Execution Memory, spill, shuffle)만 남는다. executor JVM 최대 메모리는
   `spark.eventLog.logStageExecutorMetrics=true`, `spark.executor.processTreeMetrics.enabled=true` 추가가 필요하다.
   UC08 학습(Spark 밖)은 `src/common/jobs.py`의 `run_job` 뒤에서 `resource.getrusage(RUSAGE_CHILDREN).ru_maxrss`로 기록한다.
   컨테이너 전체는 `docker stats`를 1~2초 간격으로 기록한다.

### 측정 기계

Apple M2, 8코어, RAM 24GB. Docker Desktop 메모리 16GB(기본 8GB에서 올려야 함), CPU 8.
M2 결과(M4 Pro)와 시간은 비교하지 않는다. 둘 다 arm64라 점수(MSLE 4.0136, accuracy 0.6934)는 같아야 한다.

### SF3 생성 결정

M2 README 3절(커밋 `2239421`, 11/17)에서 확정됐다. 그 표를 따른다.

- 키트 드라이버와 같은 규칙: 학습 `-sf SF` 시드 1234, 서빙 `-sf SF` 시드 1235, 채점 **`-sf 1` 고정**, 시드 `1234 + SF`(SF3이면 1237).
  SF1은 이 규칙 그대로라 다시 만들지 않는다.
- 따라서 **채점 데이터는 SF와 무관하게 SF1 크기**(order 520,000)다. SF3에서 학습·서빙만 커지므로,
  결과는 학습·서빙·채점을 따로 보고하고 보고서에 "채점은 키트 규칙상 고정"이라고 적는다.
- SF는 PDGF `-sf` 값이다(키트 드라이버의 GB 단위 SF와 다름). M2와 비교하도록 PDGF 값으로 SF3·SF10을 만든다.
- 생성 환경: x86 Linux + Temurin 8u432에서 `gen_data.sh`의 컨테이너 안 명령을 직접 실행. SF1 14개 파일이 기존 데이터와 md5로 같았다.
  Mac(네이티브, amd64 에뮬레이션)에서는 안 된다.

## 알려진 위험

- SF10: SF1에서 XGBoost 기울기 버퍼가 약 1.5GB였으므로 비례 추정 약 15GB. Docker 16GB에서 UC08 학습 실패 가능성이 크다.
  실패하면 `--workloads uc03`으로 전처리만 재거나 한계 지점 자체를 결과로 보고한다.
- UC08 학습은 Spark 밖 단일 프로세스이고 작업 시간의 63~73%다. 암달의 법칙상 전체 speedup 상한은 약 1.4~1.6배.
  전체 시간과 Spark 전처리 구간 시간을 따로 보고한다.
- 워커가 2대라 executor를 2개 넘게 늘리려면 executor를 쪼개거나 워커를 추가해야 한다.
- Mac 한 대 위의 Docker라 워커 간 통신이 실제 네트워크가 아니다. 한계로 명시한다.

## 분석과 산출물

1. 단계별 시간 분해(적재, 조인, 집계, 학습, 예측), 평균 ± 표준편차
2. separate vs shared 전처리 합계(`train/serve/score`의 `preprocess`), SF1과 SF3에서 결론이 바뀌는지
3. executor 1 → 2 speedup(전체 / Spark 전처리 구간)
4. SF1 → SF3 단계별 시간 증가 비율과 실제 데이터 크기 증가 비율
5. 한계, M1·M2 계획 대비 변경점

결과 합치기: `python tools/compare_runs.py runs/*` → `runs/all_stages.csv`.

## 일정

| 날짜 | 할 일 |
| --- | --- |
| 11/17 (화) | SF1 재현, 측정 기계 확정, SF3 생성 요청 |
| 11/18 (수) | 묶음 A, B, C |
| 11/19 (목) | 묶음 D, SF10 1회 시도 (SF3 없으면 샘플링으로 전환) |
| 11/20~21 | 결과 합치기, 그래프, 보고서 초안 |
| 11/22~23 | 발표 자료, 팀 검토 |
| 11/24 (화) | 완료 |

## 첫 단계: SF1 재현

`M2/`에서 실행한다. Docker Desktop 메모리는 16GB 이상.

```bash
docker compose build
docker compose up -d
docker compose exec client docker/load_hdfs.sh 1
docker compose exec client docker/run_cluster.sh 1 2 3 4g
```

MSLE 4.01, accuracy 0.693이 나오면 환경이 맞다(Apple Silicon 기준).
