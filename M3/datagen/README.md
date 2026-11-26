# M3 데이터 생성 (PDGF SF1·SF3·SF9·SF10)

11/21 x86 VM에서 생성하고 검증했다. 데이터 자체는 TPC 라이선스 대상이라 저장소에 넣지 않고, 이 폴더에는 스크립트와 기록만 둔다.

## 생성 방법

- `gen_sf.sh <SF>`: [M2/README.md 3절](../../M2/README.md) PDGF 명령 블록을 **수정 없이** 옮기고 경로(`J`, `KIT`, 출력 `R`)만 채운 스크립트.
  시드·옵션은 킷 드라이버 `driver/tpcxai-driver/data_generation.py`(35·44·54행 템플릿, 93·105·116행 시드)와 같다.
- 환경: Ubuntu VM(x86, 4 vCPU, 7.2GiB), Temurin 8u432(`~/Applications/m3/jdk8u432-b06`), 킷 v2.0.0(`~/Applications/m3/tpcx-ai-v2.0.0`).
  M2 담당자가 SF1을 검증한 환경과 같다. Docker(`M2/docker/gen_data.sh`)는 쓰지 않았다.
- 출력: VM 로컬 디스크 `~/Works_ub/m3data/data/sf<SF>/` (공유 폴더에 직접 쓰지 않음).
- `validate_sf.sh <data root> <log dir> SF...`: 생성 뒤 검증(아래).

```bash
M3/datagen/gen_sf.sh 1     # 기본: J, KIT는 위 경로, OUT_ROOT=~/Works_ub/m3data/data
M3/datagen/validate_sf.sh ~/Works_ub/m3data/data ~/Works_ub/m3data 1 3 9 10
```

## SF와 데이터 크기: SF에 비례하지 않는다

킷 `data-gen/config/tpcxai-schema.xml`의 크기 공식:

- 고객 = `100000 × √SF × TTVF` (33행), 주 수 = `max(104, (floor(log10 SF) + 2) × 52)` (46행)
- 주문 = `floor(고객 × 0.5 × 주 수)` (68행), 상품 = `floor(1000 × √SF)` (87행), 매장 = `round(√SF + 10)` (58행), store_dept = 매장 × 68
- 채점은 항상 `-sf 1`이라 크기가 고정이다.

| | SF1 | SF3 | SF9 | SF10 |
| --- | --- | --- | --- | --- |
| training order | 5,200,000 | 9,006,664 | 15,600,000 | 24,665,765 |
| training lineitem | 32,565,017 | 56,387,690 | 97,680,906 | 154,443,824 |
| **SF1 대비** | 1 | **1.73** | **3.00** | **4.74** |
| serving order / lineitem | 520,000 / 3,261,300 | 900,666 / 5,640,803 | 1,560,000 / 9,773,645 | 2,466,576 / 15,458,093 |
| product / store_dept (train·serve) | 1,000 / 748 | 1,732 / 816 | 3,000 / 884 | 3,162 / 884 |
| 학습 기간 (training order 날짜) | 104주, 2010-01-04 ~ 2012-01-01 | 같음 | 같음 | **156주**, 2010-01-04 ~ 2012-12-30 |
| serving 날짜 | 2012-01-02 ~ 2013-12-29 | 같음 | 같음 | 2012-12-31 ~ 2015-12-27 |
| scoring | order 520,000, 2012-01-02 ~ 2013-12-29 | 같음 | 같음 | order 520,000, **2012-12-31 ~ 2014-12-28** |
| 디스크 (CSV) | 944MB | 1.6GB | 2.8GB | 4.4GB |
| 생성 시간 / PDGF 최대 메모리 | 1분 16초 | 1분 22초 | 1분 17초 / 3.0GB | 2분 14초 / 2.9GB |

- SF1→SF3→SF9는 **고객만** 늘어난다(기간 2년 고정, √SF 배). SF10은 고객(√10)과 **기간(2년→3년)이 함께** 늘어 4.74배이고,
  serving·scoring 날짜도 1년 뒤로 옮겨진다(`START_YEAR_OFFSET`). 보고서에서 이 둘을 구분한다.
- scoring은 행 수가 모든 SF에서 같지만 시드(`1234 + SF`)가 달라 내용은 다르다. SF1에서는 scoring 시드가 serving 시드(1235)와 같아
  serving과 scoring의 order·lineitem·product·store_dept가 바이트 단위로 같다(킷 규칙의 결과).
- 킷 드라이버는 세 단계 모두 `order_weekly_sales`를 넣지만 README 블록은 scoring에만 넣는다. 이 테이블은
  `tpcxai-generation.xml` 532행에서 `includeLabels >= 2`(scoring)일 때만 `store_dept_labels.csv`를 쓰고, 다른 테이블이 참조하지 않으므로 결과 파일은 같다.

## 검증 결과 (records/)

| 무엇 | 결과 | 파일 |
| --- | --- | --- |
| SF1 재현 | M2 SF1 14개 파일과 md5 **14/14 일치** | `sf1_reference.md5`, `sf1_md5check.txt` |
| 구조·무결성 (SF1·3·9·10) | **88개 항목 전부 통과** | `validation_report.txt` |
| 생성 로그 | PDGF 3단계 모두 `All work done`, Exception 없음 | `gen_sf<SF>.log` (라이선스 문구 제외한 요약), `gen_sf<SF>.time` |
| 전송용 해시 | 파일 14개별 sha256, 압축 파일 sha256 | `sf<SF>.sha256`, `sf<SF>_data.tar.gz.sha256` |

- 검증 항목: 로그, 파일 14개·헤더·마지막 줄바꿈(잘림 여부), 행 수 = 스키마 공식 값, order ID 1..N 연속·필드 수·빈 값·날짜 형식,
  lineitem의 order ID 범위·정렬·**모든 주문에 line 1개 이상**·product ID 범위, scoring `order_labels` ID 일치.
- `validation_report_v1.txt`는 첫 실행 기록이다. serving `store_dept` 헤더 기대값을 스크립트에 잘못 넣어(serving에도 `periods` 열이 있다)
  4건 FAIL이 났고, 스크립트를 고쳐 전체를 다시 돌린 결과가 `validation_report.txt`다.
- 부서 이름 3개(`"BOYS WEAR, 4-6X AND 7-14"`, `"LIQUOR,WINE,BEER"`, `"CANDY, TOBACCO, COOKIES"`)는 따옴표 안에 쉼표가 있다.
  M2 원본도 같고 Spark CSV 파서는 문제없지만, awk·cut으로 분석할 때는 주의한다.

## 전송 (VM → Mac)

공유 폴더 `Works/26-2-Yonsei/m3data/` (저장소 밖):

| 파일 | 크기 |
| --- | --- |
| `sf3_data.tar.gz` | 468MB |
| `sf9_data.tar.gz` | 812MB |
| `sf10_data.tar.gz` | 1.28GB |
| `sf<SF>_data.tar.gz.sha256`, `sf<SF>.sha256`, `gen_sf<SF>.log`, `validation_report.txt` | |

압축은 `tar -czf sf<SF>_data.tar.gz -C data sf<SF>`라서 풀면 `sf<SF>/{training,serving,scoring}`이 생긴다.
SF1은 Mac의 `M2/data/sf1`(팀 드라이브 `sf1_data.tar.gz`)과 같으므로 보내지 않았다(Mac에서 `M3/m3data/sf1`로 복사).
Mac에서는 `M3/m3data/`에 복사해 풀고 확인한다: [M3_PLAN.md](../M3_PLAN.md) 5.0절.
VM 원본(`~/Works_ub/m3data/data/`)은 Mac 확인이 끝날 때까지 지우지 않는다.
