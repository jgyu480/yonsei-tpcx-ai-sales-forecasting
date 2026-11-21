"""Summarize Spark event logs. Run from M2/runs, or pass --runs."""
import argparse
import csv
import json
import re
from contextlib import contextmanager
from pathlib import Path

RUN = re.compile(r"m3_.*_r[123]_(separate|shared)")
MIB = 1024**2


@contextmanager
def open_events(path):
    if path.suffix == ".zstd":
        import zstandard
        with zstandard.open(path, "rt", encoding="utf-8") as stream:
            yield stream
    else:
        with path.open(encoding="utf-8") as stream:
            yield stream


def summarize_run(run):
    paths = sorted((run / "spark-events").rglob("events_*"))
    paths = [p for p in paths if p.is_file()]
    if not paths:
        raise ValueError(f"No Spark event log for {run.name}")
    added, active = set(), set()
    peak = removals = tasks = failed = 0
    spill_memory = spill_disk = shuffle_read = shuffle_write = 0
    for path in paths:
        with open_events(path) as events:
            for line in events:
                event = json.loads(line)
                kind = event.get("Event")
                if kind == "SparkListenerExecutorAdded":
                    executor = event["Executor ID"]
                    added.add(executor)
                    active.add(executor)
                    peak = max(peak, len(active))
                elif kind == "SparkListenerExecutorRemoved":
                    removals += 1
                    active.discard(event["Executor ID"])
                elif kind == "SparkListenerTaskEnd":
                    tasks += 1
                    failed += event.get("Task End Reason", {}).get("Reason") != "Success"
                    metrics = event.get("Task Metrics") or {}
                    spill_memory += metrics.get("Memory Bytes Spilled", 0)
                    spill_disk += metrics.get("Disk Bytes Spilled", 0)
                    reads = metrics.get("Shuffle Read Metrics") or {}
                    shuffle_read += reads.get("Remote Bytes Read", 0) + reads.get("Local Bytes Read", 0)
                    shuffle_write += (metrics.get("Shuffle Write Metrics") or {}).get("Shuffle Bytes Written", 0)
    if not tasks:
        raise ValueError(f"No Spark tasks found in {run.name}")
    return dict(run_id=run.name, executors_added=len(added), executors_removed=removals,
                tasks=tasks, failed_tasks=failed, spill_memory_MB=round(spill_memory/MIB, 1),
                spill_disk_MB=round(spill_disk/MIB, 1), shuffle_read_MB=round(shuffle_read/MIB, 1),
                shuffle_write_MB=round(shuffle_write/MIB, 1), peak_active_executors=peak)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--runs", type=Path, default=Path("."))
    args = parser.parse_args()
    runs = sorted(p for p in args.runs.iterdir() if p.is_dir() and RUN.fullmatch(p.name))
    if not runs:
        raise ValueError(f"No measured runs in {args.runs}")
    rows = [summarize_run(run) for run in runs]
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Wrote {len(rows)} Spark run summaries to {args.output}")


if __name__ == "__main__":
    main()
