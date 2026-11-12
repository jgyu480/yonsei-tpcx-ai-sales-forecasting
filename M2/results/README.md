# M2 실행 기록 (SF1)

보고서 수치의 근거가 되는 실행 요약이다. 예측 CSV, 모델 파일, Spark 이벤트 로그는 용량과 라이선스 때문에 넣지 않았다.
각 폴더에는 `metrics.json`(실행 조건, 단계별 시간), `stages.csv`, `validation.json`(검증 결과와 점수)이 있다.

| 폴더 | 환경 | 모델 라이브러리 | 모드 | 작업 시간(초) | UC03 MSLE | UC08 accuracy | 검증 실패 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `sf1_yarn_e2c3_kit_shared` | Docker 클러스터 (YARN, executor 2 x 3코어) | 키트 버전 | shared | 354.249 | 4.0136 | 0.6934 | 0 |
| `sf1_yarn_e2c3_kit_separate` | 같음 | 키트 버전 | separate | 291.594 | 4.0136 | 0.6934 | 0 |
| `sf1_kit_shared_w2` | x86 2코어, Spark local[2] | 키트 버전 | shared | 1310.476 | 3.9526 | 0.6934 | 0 |
| `sf1_kit_separate_w2` | 같음 | 키트 버전 | separate | 1181.089 | 3.9526 | 0.6934 | 0 |
| `sf1_shared_w2` | 같음 | 최신 버전 | shared | 1611.480 | 3.76 | 0.5668 | 1 (UC08 기준 미달) |
| `sf1_separate_w2` | 같음 | 최신 버전 | separate | 1497.694 | 3.76 | 0.5668 | 1 (UC08 기준 미달) |
| `sf1_uc03_fill` | 같음 | 최신 버전 | UC03만, 빈 주 0 채움 | 78.974 | 3.9372 | - | 0 |

- `sf1_yarn_e2c3_kit_*.log`: 두 클러스터 실행의 콘솔 로그 (2026-11-06).
- `compare_cluster_separate_vs_shared.txt`: `tools/compare_runs.py`로 두 클러스터 실행을 비교한 출력.
  예측 파일 4개가 모두 `same`이다 (UC08 클래스 완전 일치, UC03 예측값 최대 절대 차이 1e-6 미만).
- UC03 계절 모델: 키트 버전은 517쌍 모두 적합, 최신 버전은 39쌍이 단순 지수평활로 대체됐다 (`validation.json`의 `uc03.train.model_kinds`).
