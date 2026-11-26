# Team7 M3: Performance Analysis w/ Scalability Test

M2 파이프라인(UC03 + UC08)의 성능 분석과 확장성 측정. 현재 상태, 계획, 결정 사항은 [M3_PLAN.md](M3_PLAN.md) (0절부터).

## 폴더

```
M3/
  M3_PLAN.md   현재 상태, 계획, 측정 명령, 결정 사항 (인수인계 문서)
  datagen/     데이터 생성 스크립트(gen_sf.sh, validate_sf.sh)와 생성·검증 기록(records/). 설명은 datagen/README.md
  docker/      2번 축 실행용: compose override(M3/ → client /m3), m3_load.sh(HDFS 적재), m3_env.sh(측정 함수)
  m3data/      2번 축 입력 데이터 sf1·3·9·10 (gitignore)
  runs/        2번 축 실행 결과 (gitignore)
  results/     보고서에 쓰는 실행 요약 (metrics.json, stages.csv, validation.json; M2/results와 같은 형식)
  analysis/    집계·그래프 스크립트
```

- 코드는 `M2/`의 것을 고치지 않고 쓴다(`docker compose`, `run.py`). **데이터와 실행 결과는 `M3/`**(`m3data/`, `runs/`)에 둔다. 방법은 M3_PLAN.md 0·5절.
- 보고서에 쓰는 실행만 `runs/<run_id>/`에서 `metrics.json`, `stages.csv`, `validation.json`을 `results/<run_id>/`로 복사한다.
- 데이터(`m3data/`, `M2/data/`, 공유 폴더의 `m3data/`)는 TPC 라이선스 대상이라 저장소에 넣지 않는다. `M3/.gitignore`가 데이터·압축 파일·`runs/`를 막는다.
