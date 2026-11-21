"""Extract M1 Table 5 resource metrics from Spark event logs and validation files.

Run from the project root with the M2 runs directory:
    python3 scripts/16_event_metrics.py --runs <M2>/runs --output results/event_metrics

Writes
  run_metrics.csv     one row per run: tasks, executor run/CPU time, network (remote
                      shuffle bytes), shuffle/input/output bytes, spill, peak memory, GC
  worker_metrics.csv  one row per run and host: tasks, run time, records, remote bytes
  validation_summary.csv  one row per run: PASS/FAIL/INFO/WARN counts of validation.json
Compressed logs (*.zstd) are read with the `zstd` command-line tool.
"""
import argparse
import collections
import csv
import json
import re
import subprocess
from pathlib import Path

RUN = re.compile(r"m3_sf1_(?P<config>.+)_r(?P<rep>\d+)_(?P<mode>separate|shared)")
MIB = 2 ** 20


def events(path):
    if path.suffix in (".zstd", ".zst"):
        proc = subprocess.run(["zstd", "-dc", str(path)], check=True, capture_output=True)
        lines = proc.stdout.decode().splitlines()
    else:
        lines = path.read_text().splitlines()
    for line in lines:
        if line.strip():
            yield json.loads(line)


def summarize(run_dir):
    paths = sorted((run_dir / "spark-events").rglob("events_*"))
    if not paths:
        return None, None
    hosts = {}
    run = collections.Counter()
    worker = collections.defaultdict(collections.Counter)
    peak = collections.defaultdict(lambda: collections.Counter())
    for path in paths:
        for e in events(path):
            kind = e.get("Event")
            if kind == "SparkListenerExecutorAdded":
                hosts[e["Executor ID"]] = e["Executor Info"]["Host"]
            if kind != "SparkListenerTaskEnd":
                continue
            info, m = e["Task Info"], e.get("Task Metrics") or {}
            host = info.get("Host") or hosts.get(info["Executor ID"], "?")
            sr, sw = m.get("Shuffle Read Metrics", {}), m.get("Shuffle Write Metrics", {})
            inp, out = m.get("Input Metrics", {}), m.get("Output Metrics", {})
            records = inp.get("Records Read", 0) + sr.get("Total Records Read", 0)
            vals = {
                "tasks": 1,
                "failed_tasks": int(info.get("Failed", False)),
                "run_ms": m.get("Executor Run Time", 0),
                "cpu_ns": m.get("Executor CPU Time", 0),
                "gc_ms": m.get("JVM GC Time", 0),
                "remote_read_b": sr.get("Remote Bytes Read", 0),
                "local_read_b": sr.get("Local Bytes Read", 0),
                "shuffle_write_b": sw.get("Shuffle Bytes Written", 0),
                "input_b": inp.get("Bytes Read", 0),
                "output_b": out.get("Bytes Written", 0),
                "spill_disk_b": m.get("Disk Bytes Spilled", 0),
                "records": records,
            }
            run.update(vals)
            worker[host].update(vals)
            ex = peak[info["Executor ID"]]
            em = e.get("Task Executor Metrics") or {}
            ex["heap"] = max(ex["heap"], em.get("JVMHeapMemory", 0))
            ex["exec"] = max(ex["exec"], em.get("OnHeapExecutionMemory", 0))
            ex["task_peak"] = max(ex["task_peak"], m.get("Peak Execution Memory", 0))
    row = {
        "tasks": run["tasks"],
        "failed_tasks": run["failed_tasks"],
        "executor_run_s": round(run["run_ms"] / 1e3, 2),
        "executor_cpu_s": round(run["cpu_ns"] / 1e9, 2),
        "cpu_utilization_pct": round(100 * run["cpu_ns"] / 1e6 / run["run_ms"], 1) if run["run_ms"] else "",
        "gc_s": round(run["gc_ms"] / 1e3, 2),
        "network_remote_shuffle_MiB": round(run["remote_read_b"] / MIB, 1),
        "local_shuffle_read_MiB": round(run["local_read_b"] / MIB, 1),
        "shuffle_write_MiB": round(run["shuffle_write_b"] / MIB, 1),
        "input_MiB": round(run["input_b"] / MIB, 1),
        "output_MiB": round(run["output_b"] / MIB, 1),
        "spill_disk_MiB": round(run["spill_disk_b"] / MIB, 1),
        "executors_seen": len(peak),
        "peak_heap_MiB_max": round(max(p["heap"] for p in peak.values()) / MIB),
        "peak_exec_mem_MiB_max": round(max(p["exec"] for p in peak.values()) / MIB),
        "peak_task_exec_mem_MiB": round(max(p["task_peak"] for p in peak.values()) / MIB),
    }
    workers = []
    total_run = run["run_ms"] or 1
    for host, w in sorted(worker.items()):
        workers.append({
            "host": host, "tasks": w["tasks"], "executor_run_s": round(w["run_ms"] / 1e3, 2),
            "run_share_pct": round(100 * w["run_ms"] / total_run, 1),
            "executor_cpu_s": round(w["cpu_ns"] / 1e9, 2), "records": w["records"],
            "network_remote_shuffle_MiB": round(w["remote_read_b"] / MIB, 1),
        })
    return row, workers


def validation(run_dir):
    path = run_dir / "validation.json"
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    counts = collections.Counter(c.get("status") for c in data.get("checks", []))
    value = {c["check"]: c.get("value") for c in data.get("checks", [])}
    return {"checks": sum(counts.values()), "pass": counts["PASS"], "fail": counts["FAIL"],
            "warn": counts["WARN"], "info": counts["INFO"], "failed_field": data.get("failed"),
            "joined_rows": value.get("train.join.joined_rows"),
            "uc03_weekly_rows_pairs": value.get("uc03.weekly.pairs_with_sales"),
            "uc08_feature_rows_train": value.get("uc08.features.train.rows"),
            "uc03_score_msle": value.get("uc03.score.msle"),
            "uc08_score_accuracy": value.get("uc08.score.accuracy")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    runs, workers, checks = [], [], []
    for run_dir in sorted(p for p in args.runs.iterdir() if p.is_dir()):
        match = RUN.fullmatch(run_dir.name)
        if not match or int(match["rep"]) not in (1, 2, 3, 10, 11, 12, 13):
            continue
        base = {"run_id": run_dir.name, "config": match["config"], "repeat": int(match["rep"]),
                "mode": match["mode"], "set": "memory_followup" if int(match["rep"]) >= 10 else "main"}
        row, ws = summarize(run_dir)
        if row is None:
            print(f"skip (no event log): {run_dir.name}")
            continue
        runs.append({**base, **row})
        workers.extend({**base, **w} for w in ws)
        v = validation(run_dir)
        if v:
            checks.append({**base, **v})
    for name, rows in (("run_metrics.csv", runs), ("worker_metrics.csv", workers),
                       ("validation_summary.csv", checks)):
        with (args.output / name).open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    # Per-setting means over eligible runs: requested executor count seen, no failed task, no failed check.
    failed = {c["run_id"]: c["fail"] for c in checks}
    keep = []
    for row in runs:
        m = re.match(r"yarn_e(\d+)", row["config"])
        expected = int(m[1]) if m else 1
        # r10 is the memory follow-up's preliminary run and stays out of the means.
        row["eligible"] = int(row["executors_seen"] == expected and row["failed_tasks"] == 0
                              and failed.get(row["run_id"], 1) == 0 and row["repeat"] != 10)
        if row["eligible"]:
            keep.append(row)
    groups = collections.defaultdict(list)
    for row in keep:
        groups[row["set"], row["config"], row["mode"]].append(row)
    metrics = [k for k in runs[0] if k not in ("run_id", "config", "repeat", "mode", "set", "eligible")]
    summary = []
    for (kind, config, mode), rows in sorted(groups.items()):
        out = {"set": kind, "config": config, "mode": mode, "n": len(rows)}
        for k in metrics:
            out[k] = round(sum(float(r[k]) for r in rows) / len(rows), 1)
        summary.append(out)
    for name, rows in (("run_metrics.csv", runs), ("summary_by_config.csv", summary)):
        with (args.output / name).open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0]))
            writer.writeheader()
            writer.writerows(rows)
    print(f"{len(runs)} runs ({len(keep)} eligible), {len(workers)} worker rows, "
          f"{len(checks)} validation rows -> {args.output}")


if __name__ == "__main__":
    main()
