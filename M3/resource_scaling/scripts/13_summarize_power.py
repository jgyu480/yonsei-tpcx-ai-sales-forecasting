"""Aggregate host powermetrics cpu_power samples by recorded r7 run window."""
import argparse
import csv
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import mean

HEADER = re.compile(r"^\*+ Sampled system activity \((.*?)\) \(([\d.]+)ms elapsed\) \*+")
CLUSTER = re.compile(r"^([EPS]\d*)-Cluster HW active residency:\s*([\d.]+)%")
FREQUENCY = re.compile(r"^([EPS]\d*)-Cluster HW active frequency:\s*([\d.]+) MHz")
EXPECTED = ({f"m3_sf1_yarn_e2c{c}m2g_r7_separate" for c in (1, 2, 3, 4)}
            | {f"m3_sf1_local{c}_r7_separate" for c in (1, 2, 4, 8)})


def timestamp(value):
    return datetime.strptime(value, "%a %b %d %H:%M:%S %Y %z").timestamp()


def samples(path):
    stamp = None
    active, freq = {}, {}
    with path.open() as f:
        for line in f:
            if header := HEADER.match(line):
                if stamp is not None:
                    yield stamp, duration, active, freq
                stamp = timestamp(header[1])
                duration = float(header[2]) / 1000
                active, freq = {}, {}
            elif match := CLUSTER.match(line):
                active[match[1]] = float(match[2])
            elif match := FREQUENCY.match(line):
                freq[match[1]] = float(match[2])
    if stamp is not None:
        yield stamp, duration, active, freq


def summarize(log, windows, output):
    with windows.open(newline="") as f:
        runs = list(csv.DictReader(f))
    if len(runs) != 8 or {r["run_id"] for r in runs} != EXPECTED:
        raise ValueError("All eight r7 measurement windows are required")
    raw = list(samples(log))
    rows = []
    for run in runs:
        start, end = int(run["started_epoch"]), int(run["finished_epoch"])
        by_cluster = defaultdict(list)
        for stamp, elapsed, active, freq in raw:
            if start <= stamp - elapsed and stamp + 1 <= end:
                for cluster, residency in active.items():
                    by_cluster[cluster].append((residency, freq.get(cluster)))
        if not any(k.startswith("E") for k in by_cluster) or not any(k.startswith(("P", "S")) for k in by_cluster):
            raise ValueError(f"Missing P/E residency samples for {run['run_id']}")
        for cluster, observations in sorted(by_cluster.items()):
            frequencies = [freq for _, freq in observations if freq is not None]
            rows.append(dict(run_id=run["run_id"], cluster=cluster, samples=len(observations),
                             mean_active_residency_pct=round(mean(v for v, _ in observations), 2),
                             mean_active_frequency_MHz=round(mean(frequencies), 1) if frequencies else ""))
    with output.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("windows", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    summarize(args.log, args.windows, args.output)
