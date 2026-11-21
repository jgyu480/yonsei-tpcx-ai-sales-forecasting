"""Render the three SF1 resource scaling figures from the settings summary."""
import argparse
import csv
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

SERIES = {
    "scale-out": ("Scale-out", "#167D83", "o"),
    "scale-up": ("Scale-up", "#BD5528", "s"),
    "local": ("Local", "#5149A1", "^"),
}
STAGES = [
    ("spark_preprocess_mean", "Spark preprocessing", "#167D83"),
    ("uc08_train_mean", "UC08 training", "#213D60"),
    ("predict_score_etc_mean", "Other work", "#BDD0E2"),
]


def render(source, output, draft=False, report_stability_limit=False):
    with source.open(newline="") as f:
        rows = list(csv.DictReader(f))
    incomplete = any(int(row["n"]) != 3 for row in rows)
    if incomplete and not (draft or report_stability_limit):
        raise ValueError("Final charts require three repeats per setting")
    output.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.size": 11, "axes.spines.top": False,
                         "axes.spines.right": False, "axes.axisbelow": True})

    def save(fig, name):
        if draft:
            fig.text(.99, 1.02, "DRAFT · incomplete set of verified repeats",
                     ha="right", color="#BD5528", fontsize=9)
        fig.savefig(output / name, dpi=170, bbox_inches="tight", pad_inches=.22)
        plt.close(fig)

    grouped = {key: sorted((r for r in rows if r["series"] == key),
                           key=lambda r: int(r["total_cores"])) for key in SERIES}
    fig, axes = plt.subplots(1, 2, figsize=(11.5, 4.4), layout="constrained")
    for ax, metric, title in zip(axes, ("spark_preprocess", "work_total"),
                                 ("Spark preprocessing", "Entire workload")):
        for key, (label, color, marker) in SERIES.items():
            group = grouped[key]
            x = [int(r["total_cores"]) for r in group]
            y = [float(r[f"speedup_{metric}"]) for r in group]
            ax.plot(x, y, marker=marker, lw=2, label=label, color=color)
        if metric == "spark_preprocess":
            ax.plot([1, 8], [1, 8], "--", color="#788797", lw=1.2, label="Ideal (1-core baseline)")
            ax.plot([2, 8], [1, 4], ":", color="#788797", lw=1.4, label="Ideal (2-core baseline)")
            ylim = (.8, 8.3)
        else:
            # Ideal lines would flatten the measured curves near 1x; zoom in instead.
            ax.axhline(1, color="#788797", lw=1, alpha=.6)
            ylim = (.9, 1.3)
        ax.set(title=title, xlabel="Total cores / local threads", ylabel="Speedup (×)",
               xticks=(1, 2, 3, 4, 6, 8), ylim=ylim)
        ax.grid(axis="y", alpha=.25)
    axes[0].legend(frameon=False, fontsize=9, loc="upper left")
    axes[1].text(.98, .04, "Zoomed y-axis (0.9–1.3×)", transform=axes[1].transAxes,
                 ha="right", fontsize=9, color="#5F6B78")
    fig.suptitle("SF1 speedup against each series baseline", fontsize=15)
    save(fig, "01_speedup.png")

    core = [r for r in rows if r["series"] == "core"]
    fig, ax = plt.subplots(figsize=(8.2, 4.6), layout="constrained")
    x = list(range(len(core)))
    bottom = [0] * len(core)
    for key, label, color in STAGES:
        values = [float(r[key]) for r in core]
        ax.bar(x, values, width=.66, bottom=bottom, color=color, label=label)
        bottom = [a+b for a, b in zip(bottom, values)]
    for i, total in zip(x, bottom):
        ax.text(i, total + 7, f"{total:.1f}", ha="center", fontsize=10)
    labels = [
        f"{r['config'][6]} executor\n{r['mode']}"
        + (f" (n={r['n']})" if incomplete else "")
        for r in core
    ]
    ax.set(title="Join reuse with one and two YARN executors", ylabel="Mean work time (s)",
           xticks=x, xticklabels=labels, ylim=(0, max(bottom)*1.24))
    ax.legend(frameon=False, ncol=3, loc="upper center", fontsize=9)
    ax.grid(axis="y", alpha=.25)
    save(fig, "02_join_reuse.png")

    fig, axes = plt.subplots(1, 2, figsize=(10, 4.4), layout="constrained")
    for ax, metric, title in zip(axes, ("spark_preprocess", "work_total"),
                                 ("Spark preprocessing", "Entire workload")):
        for idx, (key, (label, color, _)) in enumerate(SERIES.items()):
            chosen = [r for r in grouped[key] if r["total_cores"] in {"2", "4"}]
            positions = [n + (idx-1)*.24 for n in (0, 1)]
            values = [float(r[f"{metric}_mean"]) for r in chosen]
            errors = [float(r[f"{metric}_std"]) for r in chosen]
            ax.bar(positions, values, width=.22, yerr=errors, capsize=3, label=label, color=color)
        ax.set(title=title, ylabel="Mean time ± SD (s)", xticks=(0, 1),
               xticklabels=("2 cores / threads", "4 cores / threads"))
        ax.grid(axis="y", alpha=.25)
    axes[0].legend(frameon=False, ncol=1, fontsize=9)
    fig.suptitle("SF1 at matched core counts", fontsize=15)
    save(fig, "03_matched_cores.png")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("summary", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--draft", action="store_true")
    parser.add_argument("--report-stability-limit", action="store_true")
    args = parser.parse_args()
    render(args.summary, args.output, args.draft, args.report_stability_limit)
