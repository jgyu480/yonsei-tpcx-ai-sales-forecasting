# TPCx-AI UC03 Sales Forecasting + UC08 Classification of Trips

2026-2 연세대학교 빅데이터 팀 프로젝트

## 프로젝트 범위

- 분석 워크로드: TPCx-AI UC03 — Sales Forecasting, UC08 — Classification of Trips
- 목표: 주문 데이터를 처리하여 매장·부서별 주간 판매 시계열을 만들고, 이를 이용해 미래 판매를 예측한다.
- UC03은 매장·부서별 주간 판매를 예측하고, UC08은 주문별 쇼핑 유형을 분류한다.

## 과제 요구사항

강의자료 CH2의 Team Project 안내에 따르면, 팀은 TPC의 데이터·워크로드를 선택하여 end-to-end 빅데이터 시스템을 구축하고 평가한다.

- M1 — Target Data + Workload Analysis: 보고서
- M2 — System Architecture Design & Build: 보고서와 발표
- M3 — Performance Analysis with Scalability Test: 보고서와 발표

강의자료에 표시된 M1 일정은 9월 30일이며, 일정표에는 Tentative라고 적혀 있다.

## 조사 기준

- TPCx-AI 공식 명세 버전: 2.0.0
- 공식 명세: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf
- TPC 공식 명세 목록: https://www.tpc.org/tpc_documents_current_versions/current_specifications5.asp

이 저장소의 조사 내용은 위 명세를 기준으로 작성한다. 실제 데이터 생성·구현 결과와 명세에 제시된 예상치는 구분해서 표기한다.

## Target Data: UC03·UC08 공통 입력과 UC03 예측 입력

TPCx-AI 명세 2.0.0의 데이터 정의(20~21쪽), 규모 표(23쪽), UC03 실행 설정(71쪽)을 기준으로 정리했다.

| 파일 / 테이블 | 주요 컬럼 | UC03에서의 역할 | SF1 예상 행 수 |
| --- | --- | --- | ---: |
| `order.csv` / `Order` | `o_order_id`, `date`, `store` | 주문의 날짜와 매장을 제공 | 3,676,955 |
| `lineitem.csv` / `Lineitem` | `li_order_id`, `li_product_id`, `quantity`, `price` | 주문별 상품·수량·단가를 제공 | 23,026,666 |
| `product.csv` / `Product` | `p_product_id`, `department` | 상품이 속한 부서를 제공 | 707 |
| `store_dept.csv` / `Store_dept` | `store`, `department`, `periods` | 예측할 매장·부서와 예측 주 수를 지정 | 748 |

### 데이터 연결 관계

1. `Order.o_order_id = Lineitem.li_order_id`로 주문과 주문상품을 연결한다.
2. `Lineitem.li_product_id = Product.p_product_id`로 상품의 부서를 연결한다.
3. 연결 결과의 날짜·매장·부서를 이용해 매장·부서·주 단위 판매 시계열을 만든다.

공식 실행 설정에서 **학습 단계의 입력은 `order.csv`, `lineitem.csv`, `product.csv`**이고, **예측 단계의 입력은 `store_dept.csv`**다. 따라서 `Store_dept`를 학습 단계에서 반드시 네 번째로 JOIN하는 테이블로 설명하지 않는다.

SF1의 행 수는 명세가 제시한 **생성 데이터의 예상치**이며, 우리 팀이 파일을 생성하여 측정한 값은 아니다. SF는 TPCx-AI 전체 원시 데이터의 규모를 나타내므로, SF1이 UC03 입력 파일만 정확히 1GB라는 뜻도 아니다.

출처:
- 테이블·컬럼: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=20
- SF별 예상 행 수: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=23
- UC03 학습·예측 입력 설정: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=71

## Workload: UC03 Sales Forecasting

### 공식 명세가 정의한 작업

TPCx-AI 명세 2.0.0의 UC03 설명(25쪽)에 따르면, 이 작업은 제한된 과거 판매 이력으로 각 매장·부서의 **주간 판매를 최대 1년까지 예측**한다. 명세의 논리적 흐름은 다음과 같다.

1. `Order`, `Lineitem`, `Product`를 로드하고 연결한다.
2. 매장·부서별 주간 판매 데이터를 집계한다.
3. 주간 판매 시계열의 예측 모델을 학습한다. 구체적인 구현 모델은 아래의 자료 간 차이를 확인한 뒤 확정한다.
4. `Store_dept`로 지정된 매장·부서에 대해 미래 판매를 예측한다.
5. 예측 결과를 평가한다.

공식 실행 설정도 학습에는 `order.csv`, `lineitem.csv`, `product.csv`를, 예측에는 `store_dept.csv`를 입력으로 지정한다.

### 우리가 만들 중간 데이터의 형태

JOIN과 집계를 마치면 아래와 같이 **한 행이 특정 매장·부서·주에 대응하는 시계열 테이블**을 만들 계획이다.

| Store | Dept | Date | Weekly_Sales |
| --- | --- | --- | --- |
| 매장 ID | 부서명 | 해당 주의 금요일 | 그 주의 판매 금액 |

위 컬럼은 공식 도구 v2.0.0의 Python `UseCase03.py`가 전처리 후 반환하는 형태다. 각 주문상품의 `quantity × price`를 계산하고, 매장·부서·연도·주별로 합산해 `Weekly_Sales`를 만든다. 판매 이력이 없는 주를 어떻게 다룰지는 실제 데이터와 실행 결과로 확인해야 한다.

### 워크로드에서 비용이 발생할 지점

- `Order`와 큰 `Lineitem`을 주문 ID로 연결하는 JOIN
- 상품 ID로 `Product`의 부서를 붙이는 JOIN
- 매장·부서·주별로 행을 모으는 집계
- 여러 매장·부서의 시계열에 대한 모델 학습과 예측

위 목록은 명세의 처리 흐름에서 도출한 **예상 비용 지점**이다. 실제 병목과 실행 시간은 M2·M3에서 측정한다.

출처:
- UC03 목표와 논리적 처리 흐름: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=25
- UC03 입력 파일 설정: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=71

## M2·M3로 이어질 구현 및 평가 계획

아래는 **우리 팀의 후속 계획안**이다. M1에서 이미 구현하거나 성능을 측정했다는 의미는 아니다.

### M2: 시스템 설계 및 구현

- 원본 테이블을 적재하고, `Order`–`Lineitem`–`Product` 연결 및 주간 판매 집계 파이프라인을 구현한다.
- 집계 결과를 입력으로 UC03 판매 예측을 수행하고 결과를 저장한다.
- 같은 원본 테이블로 UC08의 주문별 특징을 만들고, 쇼핑 유형 분류 모델의 예측 결과를 저장한다.
- 사용할 실행 환경과 저장 형식은 장비·데이터 생성 가능성을 확인한 뒤 결정한다.

### M3: 성능 및 확장성 평가

각 워크로드의 입력과 출력 정의를 고정하고 다음을 비교할 계획이다.

- UC03 단계별 실행 시간: 데이터 읽기, JOIN, 주간 집계, 모델 학습, 예측
- UC08 단계별 실행 시간: 데이터 읽기, JOIN, 주문별 특징 생성, 모델 학습, 분류 예측
- 데이터 규모 증가 시 전체 처리 시간과 단계별 처리 시간의 변화
- 실행 환경이 허용하면 작업자 수 변화에 따른 처리 시간과 서버 간 데이터 이동량
- 처리 방식을 바꾸는 경우, 최종 주간 판매 집계 결과가 동일한지 검증

예를 들어 작은 `Product` 테이블을 각 작업자에게 전달하는 JOIN 방식이나, 동일한 주간 집계 결과를 저장해 재사용하는 방식을 비교 대상으로 검토할 수 있다. 이는 **실험 후보**이며 실제 시스템과 비교 조건은 M2에서 확정한다.

공식 명세의 SF1, SF3, SF10은 전체 벤치마크 데이터의 서로 다른 규모다. 우리 팀이 부분 데이터나 별도로 가공한 데이터로 실험한다면 이를 공식 SF 규모의 TPCx-AI 벤치마크 결과로 표시하지 않는다.

### 구현 전 확인할 사항

- 주 경계와 판매 이력이 없는 주를 어떻게 처리하는가?
- 생성 도구 및 UC03 코드가 팀의 실행 환경에서 동작하는가?
- 실제 확보 가능한 데이터 규모와 작업자 수는 어느 정도인가?

이 항목들은 현재 확인되지 않았으므로, 보고서에서 이미 검증한 사실처럼 쓰지 않는다. UC08도 M1 분석 대상으로 포함한다. 두 워크로드의 실제 실행 가능 규모는 M2에서 확인한다.

## 자료 간 차이와 추가 검증

- TPCx-AI 2.0.0 명세의 UC03 설명은 SARIMA를 언급한다.
- TPCx-AI를 소개한 VLDB 연구 논문은 UC03 구현 모델을 Holt-Winters라고 설명한다.
- 공식 명세의 품질 기준 표에는 UC03 지표가 `Forecast accuracy`, 기준이 `5.400 이하`로 표시된다. 연구 논문은 UC03 지표를 `mean_squared_log_error`로 표기한다.
- 공식 도구 v2.0.0의 Python 실행 코드를 확인한 결과 모델과 주간 판매값 계산식은 아래와 같다. 품질 지표의 실제 계산 코드는 추가로 확인한다.

참고 자료:
- 공식 명세의 UC03 설명: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=25
- 공식 명세의 품질 기준 표: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=43
- TPCx-AI 연구 논문: https://www.vldb.org/pvldb/vol16/p3649-rabl.pdf

## M1 보고서에서 설명할 UC03·UC08 선정 이유

TPCx-AI는 데이터 생성·적재·전처리·학습·예측·평가를 포함하는 벤치마크다. 이 프로젝트는 UC03과 UC08을 선택해 같은 주문 데이터를 서로 다른 방식으로 가공하는 두 워크로드를 분석한다.

UC03에서는 대규모 `Order`와 `Lineitem`을 연결하고, `Product`로 부서를 식별한 다음 매장·부서·주 단위로 집계한다. 따라서 데이터 구조, JOIN, 집계, 중간 결과 저장, 규모 증가에 따른 처리 시간이라는 빅데이터 시스템 과목의 질문을 하나의 워크로드에서 다룰 수 있다.

UC08은 UC03과 같은 `Order`·`Lineitem`·`Product`를 사용한다. 공통 JOIN 결과를 두 작업에서 재사용할 수 있는지는 M2의 설계·실험 대상으로 검토한다. M1에서는 두 워크로드를 모두 분석하고, M2·M3에서는 각각의 구현과 성능을 평가할 계획이다.

출처:
- TPCx-AI 전체 처리 단계와 데이터 생성: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=15
- UC03 처리 흐름: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=25

### 공식 Python UC03 코드에서 확인한 처리

- 근거 파일: 공식 TPCx-AI Tools v2.0.0의 `workload/python/workload/UseCase03.py`
- 학습 입력: `order.csv`, `lineitem.csv`, `product.csv`를 pandas로 읽어 주문 ID와 상품 ID로 두 번 JOIN한다.
- 주간 판매값: `quantity × price`를 매장·부서·연도·주별로 합산한다. 전처리 결과 컬럼은 `Store`, `Dept`, `Date`, `Weekly_Sales`이며 `Date`는 해당 주의 금요일이다.
- 모델: `(Store, Dept)` 조합마다 `ExponentialSmoothing` 모델 하나를 학습한다. 설정은 가산 계절성(`seasonal='add'`), 계절 주기 52주다.
- 예측 입력: `store_dept.csv`의 각 행에서 `store`, `department`, `periods`를 읽는다.
- 예측 출력: `periods`주만큼 예측하고 음수 결과는 0으로 제한한다. 금요일 날짜와 함께 `store`, `department`, `date`, `weekly_sales` 컬럼의 `predictions.csv`를 저장한다.
- 코드의 `train()` 설명문에는 ARIMA/SARIMAX가 적혀 있지만 실행되는 모델 생성 문장은 `ExponentialSmoothing(...)`이다.
- `UseCase03.py`에는 명령행 인자로 `scoring`이 선언되어 있지만, 확인한 `main()`에는 scoring 실행 분기가 없다. 품질 지표 계산은 관련 도구 파일을 추가로 확인한다.
- 도구 검색에서 확인한 MSLE 관련 코드는 UC05의 손실 함수 선택 부분이다. 이를 UC03의 실제 평가 지표 계산 근거로 사용하지 않는다.

## Workload: UC08 Classification of Trips

### 목표와 입력 데이터

UC08은 쇼핑 거래 내역으로 주문별 쇼핑 유형(`trip_type`)을 분류하는 작업이다. UC03과 마찬가지로 학습과 예측에 `order.csv`, `lineitem.csv`, `product.csv`를 사용한다. `Order.o_order_id = Lineitem.li_order_id`, `Lineitem.li_product_id = Product.p_product_id`로 연결한다. UC08의 정답 레이블인 `trip_type`은 `Order`에 있다. 학습 데이터에는 레이블을 사용하고, 예측 단계에서는 레이블 없이 주문의 유형을 예측한다.

따라서 세 원본 파일과 JOIN 키는 UC03과 공유하지만, 가공 결과는 다르다. UC03은 매장·부서·주별 판매 시계열을 만들고, UC08은 주문 ID별 분류 특징을 만든다. SF1의 예상 행 수는 앞의 데이터 표를 참고한다. 아직 팀이 생성·측정한 데이터 규모는 아니다.

### 공식 Python UC08 코드에서 확인한 처리

근거 파일은 TPCx-AI Tools v2.0.0의 `workload/python/workload/UseCase08.py`다.

1. 세 CSV를 읽고 주문 ID와 상품 ID로 두 번 JOIN한다.
2. 주문별 구매 수량 관련 특징(`scan_count`, `scan_count_abs`), 요일 특징, 상품 부서별 특징을 만든다. 비어 있는 요일·부서 값은 0으로 채운다.
3. 학습 시 `trip_type`을 분류 레이블로 사용하며, 코드에서는 `trip_type == 14`인 행을 제외한다.
4. `XGBClassifier(tree_method='hist', objective='multi:softprob', n_estimators=num_rounds)`로 학습한다.
5. 예측 결과의 `o_order_id`, `trip_type`을 `predictions.csv`로 저장한다.

TPCx-AI 명세 2.0.0의 UC08 품질 기준은 **분류 정확도 0.650 이상**이다. 이는 벤치마크의 기준이며 우리 팀의 측정 결과가 아니다.

### 두 워크로드를 함께 분석할 이유

두 작업은 같은 대규모 `Order`·`Lineitem`과 작은 `Product`의 JOIN을 필요로 한다. 이후 UC03은 주간 판매 집계와 시계열 예측을, UC08은 주문별 특징 생성과 분류를 수행한다. M2에서는 공통 입력·JOIN 단계의 설계를 검토하고, M3에서는 각 단계의 실행 시간과 데이터 규모 증가에 따른 변화를 별도로 측정한다. 공통 JOIN 결과의 재사용은 실험 후보이며 실제 이득은 아직 확인되지 않았다.

출처:

- UC08의 목표와 처리 흐름: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=28
- `Order.trip_type`과 데이터 스키마: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=20
- UC08 학습·예측 입력 설정: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=73
- UC08 품질 기준: https://www.tpc.org/TPC_Documents_Current_Versions/pdf/TPCx-AI_v2.0.0.pdf#page=43
- 구현 확인: TPCx-AI Tools v2.0.0, `workload/python/workload/UseCase08.py`
