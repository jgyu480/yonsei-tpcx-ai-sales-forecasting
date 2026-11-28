"""Summarize the planned runs by setting, including Spark disk spill."""
import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path
from statistics import mean, stdev

SCALE_OUT = [f"yarn_e{i}c1m1g" for i in (1, 2, 3, 4)]
SCALE_UP = [f"yarn_e2c{i}m2g" for i in (1, 2, 3, 4)]
LOCAL = [f"local{i}" for i in (1, 2, 4, 8)]
CORE = ["yarn_e1c2m2g", "yarn_e2c2m2g"]
GROUPS = [
    ("scale-out", [(c, "separate") for c in SCALE_OUT]),
    ("scale-up", [(c, "separate") for c in SCALE_UP]),
    ("local", [(c, "separate") for c in LOCAL]),
    ("core", [(c, m) for c in CORE for m in ("separate", "shared")]),
]
REPEATS = (1, 2, 3)
RUN = re.compile(r"m3_sf1_(.+)_r(\d+)_(separate|shared)")
PLANNED_SETTINGS = {setting for _, group in GROUPS for setting in group}


def planned_run_ids():
    return {f"m3_sf1_{config}_r{repeat}_{mode}"
            for config, mode in PLANNED_SETTINGS for repeat in REPEATS}


def summarize(source, output, allow_partial):
    by_run = defaultdict(lambda: defaultdict(float))
    with (source / "all_stages.csv").open(newline="") as f:
        for row in csv.DictReader(f):
            run = RUN.fullmatch(row["run_id"])
            if not run or int(run[2]) not in REPEATS or row["kind"] != "work":
                continue
            seconds = float(row["seconds"])
            values = by_run[row["run_id"]]
            values["work_total"] += seconds
            if row["phase"] == "preprocess":
                values["spark_preprocess"] += seconds
            elif row["stage"] == "uc08_train":
                values["uc08_train"] += seconds
            else:
                values["predict_score_etc"] += seconds
    with (source / "spark_event_summary.csv").open(newline="") as f:
        events = {r["run_id"]: r for r in csv.DictReader(f)}
    settings = defaultdict(list)
    for rid, values in by_run.items():
        config, repeat, mode = RUN.fullmatch(rid).groups()
        event = events[rid]
        if not int(event["tasks"]):
            raise ValueError(f"Missing Spark task data for {rid}")
        values["spill_disk_MiB"] = float(event["spill_disk_MB"])
        settings[config, mode].append((repeat, values))
    expected = planned_run_ids()
    if set(settings) != PLANNED_SETTINGS or set(by_run) - expected or (not allow_partial and set(by_run) != expected):
        raise ValueError(f"Expected the planned settings and {len(expected)} runs. Found {len(by_run)} runs.")
    metrics = ("spark_preprocess", "uc08_train", "predict_score_etc", "work_total", "spill_disk_MiB")
    stats = {}
    for key, observations in settings.items():
        repeats, values = zip(*observations)
        if not allow_partial and set(repeats) != {str(repeat) for repeat in REPEATS}:
            raise ValueError(f"{key} has repeats {repeats}")
        stats[key] = {"n": len(values)}
        for metric in metrics:
            samples = [v[metric] for v in values]
            stats[key][f"{metric}_mean"] = mean(samples)
            stats[key][f"{metric}_std"] = stdev(samples) if len(samples) > 1 else None
    rows = []
    for series, group in GROUPS:
        baseline = stats[group[0]]
        for config, mode in group:
            cores = (int(config[5:]) if config.startswith("local") else
                     int(config[6]) * int(config[8]))
            row = dict(series=series, config=config, mode=mode, total_cores=cores,
                       **stats[config, mode])
            for metric in ("spark_preprocess", "work_total"):
                key = f"{metric}_mean"
                row[f"speedup_{metric}"] = baseline[key] / row[key]
            rows.append({k: round(v, 4) if isinstance(v, float) else v for k, v in row.items()})
    with output.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--allow-partial", action="store_true", help="Generate a draft before reruns finish")
    args = parser.parse_args()
    summarize(args.results, args.output, args.allow_partial)
