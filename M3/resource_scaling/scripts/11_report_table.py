"""Create a report-ready Markdown table from a verified settings summary."""
import argparse
import csv
from pathlib import Path


def make_table(summary, report_stability_limit=False):
    with summary.open(newline="") as f:
        rows = list(csv.DictReader(f))
    yield "# 표 1. SF1 설정별 작업 시간과 스필"
    if any(int(row["n"]) != 3 for row in rows):
        yield ""
        if report_stability_limit:
            yield "**안정성 한계.** executor 교체가 확인된 실행은 성능 평균에서 제외했다. 표의 n은 설정별 유효 반복 수이며, n=1의 표준편차는 표시하지 않는다."
        else:
            yield "**잠정 결과.** 일부 설정의 반복 수가 3회 미만이며, n=1의 표준편차는 표시하지 않는다."
    yield ""
    yield "시간은 초, 스필은 MiB로 표시한다. 시간과 스필은 평균 ± 표본 표준편차로 표시한다."
    yield "속도 향상은 계열별 기준 설정의 평균 시간 ÷ 해당 설정의 평균 시간이다."
    yield ""
    yield "| 계열 | 설정 | 모드 | 코어 | n | Spark 전처리 (s) | UC08 학습 (s) | 전체 작업 (s) | 전처리 향상 | 전체 향상 | 디스크 스필 (MiB) |"
    yield "|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|"
    for row in rows:
        def interval(metric):
            average = float(row[f"{metric}_mean"])
            spread = row[f"{metric}_std"]
            return f"{average:.1f} ± {float(spread):.1f}" if spread else f"{average:.1f}"
        yield (f"| {row['series']} | {row['config']} | {row['mode']} | {row['total_cores']} "
               f"| {row['n']} | {interval('spark_preprocess')} | {interval('uc08_train')} "
               f"| {interval('work_total')} | {float(row['speedup_spark_preprocess']):.2f}× "
               f"| {float(row['speedup_work_total']):.2f}× | {interval('spill_disk_MiB')} |")
    yield ""
    yield "Scale-out과 local은 코어 1개, scale-up은 코어 2개가 기준이다. 핵심 모드 비교의 기준은 executor 1개 separate다."
    yield "핵심 비교의 2 executor separate와 scale-up의 4코어 설정은 같은 측정이다."


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--report-stability-limit", action="store_true")
    args = parser.parse_args()
    args.output.write_text("\n".join(make_table(args.summary, args.report_stability_limit)) + "\n", encoding="utf-8")
