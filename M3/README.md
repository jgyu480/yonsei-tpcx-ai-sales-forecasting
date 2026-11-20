# Team7 M3: Performance Analysis w/ Scalability Test

M2 파이프라인(UC03 + UC08)의 성능 분석과 확장성 측정. 계획과 결정 사항은 [M3_PLAN.md](M3_PLAN.md).

## 폴더

```
M3/
  M3_PLAN.md   계획, 확인 결과, 결정 사항
  results/     보고서에 쓰는 실행 요약 (metrics.json, stages.csv, validation.json; M2/results와 같은 형식)
  analysis/    집계·그래프 스크립트
```

- 코드와 실행은 `M2/`에서 한다(`docker compose`, `run.py`, `docker/run_cluster.sh`). 실행 결과는 `M2/runs/`에 쌓이고 git에서 제외된다.
- 보고서에 쓰는 실행만 `M2/runs/<run_id>/`에서 `metrics.json`, `stages.csv`, `validation.json`을 `M3/results/<run_id>/`로 복사한다.
- 데이터(`M2/data/`)는 TPC 라이선스 대상이라 저장소에 넣지 않는다.
