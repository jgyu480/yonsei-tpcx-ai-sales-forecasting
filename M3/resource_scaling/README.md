# M3 · 자원 확장 실험 (Resource Scaling)

SF1에서 **UC03 매출 예측**과 **UC08 쇼핑 유형 분류**를 실행한다. 두 작업은 Order, Lineitem, Product 조인을 공통으로 사용한다. `separate` 모드는 각 작업에서 조인하고, `shared` 모드는 조인 결과를 한 번 저장한 뒤 두 작업에서 재사용한다.

자원 확장 실험에서는 입력을 SF1로 고정하고 Spark executor 개수, executor당 코어 수 또는 로컬 스레드 수를 바꾼다. 데이터 확장 실험은 별도의 축이다.

## 자원 확장 실험 실행

팀에서 제공한 `sf1_data.tar.gz`를 저장소 밖에 보관하고 경로를 `TARBALL`에 지정한다. Apple Silicon MacBook Air M5 16GB 기준 Docker Desktop은 CPU 8개, 메모리 12GB, 스왑 2GB로 설정한다. 초기 준비 스크립트가 별도의 작업 복사본을 만들고 M2를 `2239421`로 체크아웃한 뒤, 데이터 검증·적재 및 워밍업을 수행한다.

```bash
cd M3/resource_scaling
export WORK="$HOME/m3work"
export TARBALL="/path/to/sf1_data.tar.gz"
bash scripts/01_setup.sh
bash scripts/02_smoke_test.sh
bash scripts/03_run_night1.sh
bash scripts/04_run_night2.sh
bash scripts/05_collect.sh  # 후속 측정 전에는 분석 대상 41건
```

메모리 시험 두 건은 각각 `checks failed: 0`을 확인한다. 측정은 한 번에 하나씩 실행한다. `07_rerun.sh`는 이 실험에서 executor가 교체됐던 세 건을 다시 측정하고, 로컬 3회차와 P/E 코어 관측을 추가하는 후속 작업이다. 기존 측정 결과와 macOS 관리자 인증이 필요하다.

```bash
bash scripts/07_rerun.sh
python3 -m pip install matplotlib zstandard
REPORT_STABILITY=1 bash scripts/10_prepare_results.sh  # 45건 보존 및 성능 집계
python3 scripts/13_summarize_power.py \
  results/powermetrics_r7.log results/powermetrics_windows.csv results/power_summary.csv
```

`RERUN_PHASE=timing`으로 교체·로컬 3회차만, `RERUN_PHASE=power`로 P/E 코어 관측만 실행할 수 있다. 두 단계는 순서대로 실행한다. `power_summary.csv`는 대기 시간을 제외한 r7 실행 구간의 호스트 전체 코어 클러스터 사용률을 담는다.

Spark 전처리와 전체 작업 시간을 따로 비교한다. 전체 작업 시간에는 모델 학습과 예측·채점이 들어가고 검증과 초기 데이터 적재는 제외한다. 시간 분석에서는 로컬 준비 실행(r0), P/E 코어 관측(r7), 메모리 시험(r9)을 제외한다.

[자원 확장 실험 설계](DECISIONS.md)

SF1 압축 파일과 원본 데이터, 원본 Spark 이벤트 및 powermetrics 로그는 저장소에 포함하지 않는다.

교체 측정 후에도 e1c2 shared r2·r3에서 executor 교체가 재현되어, 두 건은 성능 평균에서 제외했다. 실행 기록은 45건, 성능 표본은 43건이다. Spark 요약 CSV의 timing_eligible 열에 포함 여부를 남겼다.

[P/E 코어 관측 요약](power-analysis.md) · [설정별 관측 CSV](results/power_summary.csv)

## 보충 실험 · executor 힙 3 GiB

기존 2 GiB에서 executor 교체가 반복된 SF1 shared 설정(1 executor, 2코어)을 대상으로 한다. Docker 메모리 12 GiB, 드라이버 3 GiB와 셔플 파티션 24개는 유지한다. shared 예비 실행(r10)이 결과 검증을 통과하고 executor 교체 및 실패 태스크가 모두 0건일 때 r11–r13에서 두 모드를 회차별로 번갈아 측정한다. r10–r13은 원래 성능 집계와 분리한다.

기존 SF1 클러스터가 준비된 상태에서, `M3/resource_scaling` 폴더에서 실행한다.

```bash
python3 -m pip install zstandard
bash scripts/14_memory_followup.sh
python3 scripts/15_summarize_memory.py \
  --runs "${WORK:-$HOME/m3work}/yonsei-tpcx-ai-sales-forecasting/M2/runs" \
  --output results/memory_followup
```

[3 GiB 보충 실험 결과](results/memory_followup/README.md)

## M1 약속 지표 · Spark 이벤트 로그 집계

M1 표 5의 자원 증가 비교 항목(워커별 시간, CPU, 네트워크 전송)과 separate·shared 비교 항목(피크 메모리, 임시 저장 공간, 정확성)을 실행별 Spark 이벤트 로그와 `validation.json`에서 집계한다. 압축 로그를 풀 때 `zstd` 명령이 필요하다.

```bash
python3 scripts/16_event_metrics.py \
  --runs "${WORK:-$HOME/m3work}/yonsei-tpcx-ai-sales-forecasting/M2/runs" \
  --output results/event_metrics
```

`run_metrics.csv`는 실행별 지표, `worker_metrics.csv`는 실행·워커별 지표, `validation_summary.csv`는 검증 결과와 모델 점수, `summary_by_config.csv`는 교체 없는 실행의 설정별 평균이다. 지표는 Spark 태스크만 대상으로 하며 별도 Python 프로세스에서 도는 UC08 학습은 포함하지 않는다.
