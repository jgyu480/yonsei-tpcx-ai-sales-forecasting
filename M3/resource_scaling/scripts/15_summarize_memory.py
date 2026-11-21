"""Report the isolated SF1 3 GiB experiment without changing the original results."""
import argparse
import csv
import json
import runpy
from pathlib import Path
from statistics import mean, stdev

ROOT = Path(__file__).resolve().parents[1]
EVENTS = runpy.run_path(str(ROOT / "scripts/06_spark_event_summary.py"))


def load_run(runs, repeat, mode):
    path = runs / f"m3_sf1_yarn_e1c2m3g_r{repeat}_{mode}"
    event = EVENTS["summarize_run"](path)
    validation = json.loads((path / "validation.json").read_text())
    if validation["run_id"] != path.name:
        raise ValueError(f"Validation does not match {path.name}")
    with (path / "stages.csv").open(newline="") as f:
        work = [r for r in csv.DictReader(f) if r["kind"] == "work"]
    if not work or {r["run_id"] for r in work} != {path.name}:
        raise ValueError(f"Missing or mismatched stage times: {path.name}")
    return {
        "run_id": path.name,
        "repeat": repeat,
        "mode": mode,
        "validation_failed": validation["failed"],
        "executors_added": event["executors_added"],
        "peak_active_executors": event["peak_active_executors"],
        "failed_tasks": event["failed_tasks"],
        "eligible": int(validation["failed"] == 0 and event["failed_tasks"] == 0
                        and event["executors_added"] == event["peak_active_executors"] == 1),
        "spark_preprocess_s": round(sum(float(r["seconds"]) for r in work if r["phase"] == "preprocess"), 3),
        "work_s": round(sum(float(r["seconds"]) for r in work), 3),
        "spill_disk_MiB": event["spill_disk_MB"],
    }


def format_stat(rows, metric):
    values = [r[metric] for r in rows]
    if len(values) > 1:
        return f"{mean(values):.1f} ± {stdev(values):.1f}"
    return f"{values[0]:.1f}" if values else "—"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    pilot = load_run(args.runs, 10, "shared")
    formal = [load_run(args.runs, rep, mode) for rep in (11, 12, 13)
              for mode in ("separate", "shared")] if pilot["eligible"] else []
    args.output.mkdir(parents=True, exist_ok=True)
    with (args.output / "runs.csv").open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(pilot))
        writer.writeheader()
        writer.writerows([pilot, *formal])

    contents = [
        "# SF1 보충 실험 · executor 힙 3 GiB",
        "",
        "Docker 12 GiB, executor 1개 × 2코어, 드라이버 3 GiB, 셔플 파티션 24개를 유지했다.",
        f"shared 예비 실행은 {'통과' if pilot['eligible'] else '미통과'}했다. "
        f"등록 executor {pilot['executors_added']}개, 피크 {pilot['peak_active_executors']}개, "
        f"실패 태스크 {pilot['failed_tasks']}건, 결과 검증 실패 {pilot['validation_failed']}건이었다.",
        "",
    ]
    if formal:
        contents.extend([
            "예비 실행은 평균에서 제외했다. 결과 검증과 executor·태스크 판정을 모두 통과한 표본의 평균 ± 표본 표준편차다.",
            "",
            "| 모드 | 실행 완료 | 결과 검증 통과 | 교체 발생 | 유효 표본 | Spark 전처리(s) | 전체 작업(s) | 디스크 스필(MiB) |",
            "|---|---:|---:|---:|---:|---:|---:|---:|",
        ])
        for mode in ("separate", "shared"):
            observations = [r for r in formal if r["mode"] == mode]
            good = [r for r in observations if r["eligible"]]
            validation_passed = sum(r["validation_failed"] == 0 for r in observations)
            replacements = sum(r["executors_added"] > r["peak_active_executors"] for r in observations)
            stats = " | ".join(format_stat(good, key) for key in ("spark_preprocess_s", "work_s", "spill_disk_MiB"))
            contents.append(f"| {mode} | {len(observations)} | {validation_passed} | {replacements} | {len(good)} | {stats} |")
        contents.extend(["", "| 회차 | 전체 작업 차이 shared − separate (s) |",
                         "|---|---:|"])
        for rep in (11, 12, 13):
            paired = {r["mode"]: r for r in formal if r["repeat"] == rep and r["eligible"]}
            delta = f"{paired['shared']['work_s'] - paired['separate']['work_s']:+.1f}" if len(paired) == 2 else "비교 제외"
            contents.append(f"| {rep} | {delta} |")
    else:
        contents.append("사전에 정한 예비 실행 기준을 충족하지 못해 본 측정을 진행하지 않았다.")
    contents.extend(["", "2 GiB 측정과 수행 시점이 다르므로 메모리 증설만의 인과 효과로 해석하지 않는다. "
                     "보충 측정은 기존 성능 집계 및 P/E 관측에 합치지 않았다.", ""])
    (args.output / "README.md").write_text("\n".join(contents), encoding="utf-8")


if __name__ == "__main__":
    main()
