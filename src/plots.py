"""Charts. One function per analysis question; a shared house style.

Rules (see config.py for the palette): labelled axes, real titles, no default
matplotlib blue, categorical hues used in fixed order, no dual y-axis - a second
measure on a different scale gets its own panel. Every function returns the
path of the PNG it wrote to figures/.
"""

from __future__ import annotations

from pathlib import Path

import matplotlib as mpl

mpl.use("Agg")  # write PNGs, never open a window (also fixes flaky Tk on Windows)

import matplotlib.pyplot as plt  # noqa: E402
import matplotlib.ticker as mtick  # noqa: E402
import pandas as pd  # noqa: E402

from .config import CATEGORICAL, DIVERGING, FIGURES_DIR, INK, PRIMARY, STATUS, SURFACE


# --------------------------------------------------------------------------- #
# House style
# --------------------------------------------------------------------------- #
def apply_style() -> None:
    mpl.rcParams.update(
        {
            "figure.facecolor": SURFACE,
            "axes.facecolor": SURFACE,
            "savefig.facecolor": SURFACE,
            "savefig.bbox": "tight",
            "font.family": "sans-serif",
            "font.sans-serif": ["Segoe UI", "DejaVu Sans", "Arial"],
            "font.size": 11,
            "axes.titlesize": 13,
            "axes.titleweight": "bold",
            "axes.titlelocation": "left",
            "axes.titlepad": 10,
            "axes.labelsize": 10,
            "axes.labelcolor": INK["secondary"],
            "axes.edgecolor": INK["baseline"],
            "axes.linewidth": 0.8,
            "axes.spines.top": False,
            "axes.spines.right": False,
            "axes.grid": True,
            "axes.grid.axis": "y",
            "axes.axisbelow": True,
            "grid.color": INK["grid"],
            "grid.linewidth": 0.6,
            "xtick.color": INK["muted"],
            "ytick.color": INK["muted"],
            "xtick.labelcolor": INK["secondary"],
            "ytick.labelcolor": INK["secondary"],
            "text.color": INK["primary"],
            "figure.titlesize": 14,
            "figure.titleweight": "bold",
        }
    )


def save_fig(fig: plt.Figure, name: str) -> Path:
    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    path = FIGURES_DIR / (name if name.endswith(".png") else f"{name}.png")
    fig.savefig(path, dpi=150)
    plt.close(fig)
    print(f"  wrote {path.name}")
    return path


def _labels(ax, bars, fmt="{:.2f}", pad=0.01, color=None, horizontal=False):
    for bar in bars:
        if horizontal:
            v = bar.get_width()
            ax.annotate(fmt.format(v), (v, bar.get_y() + bar.get_height() / 2),
                        xytext=(4, 0), textcoords="offset points",
                        va="center", ha="left", fontsize=9,
                        color=color or INK["secondary"])
        else:
            v = bar.get_height()
            ax.annotate(fmt.format(v), (bar.get_x() + bar.get_width() / 2, v),
                        xytext=(0, 3), textcoords="offset points",
                        va="bottom", ha="center", fontsize=9,
                        color=color or INK["secondary"])


# --------------------------------------------------------------------------- #
# Q1 - delivery time vs review score
# --------------------------------------------------------------------------- #
def plot_q1_delivery_buckets(df: pd.DataFrame) -> Path:
    df = df.sort_values("delivery_bucket")
    x = df["delivery_bucket"].to_list()

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(9, 7), sharex=True)

    b1 = ax1.bar(x, df["mean_review_score"], color=PRIMARY, width=0.62)
    _labels(ax1, b1, "{:.2f}")
    ax1.set_ylabel("Mean review score (1-5)")
    ax1.set_ylim(1, 5)
    ax1.set_title("Review score holds until ~20 days, then collapses")

    b2 = ax2.bar(x, df["pct_one_star"] * 100, color=STATUS["critical"], width=0.62)
    _labels(ax2, b2, "{:.0f}%", color=INK["secondary"])
    ax2.set_ylabel("Share of 1-star reviews")
    ax2.set_xlabel("Delivery time  (purchase → customer)")
    ax2.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax2.set_title("1-star reviews go from 1 in 20 to 2 in 3")

    fig.suptitle("Q1  Delivery time vs review score  ·  95,824 delivered + reviewed orders")
    fig.align_ylabels()
    fig.tight_layout()
    return save_fig(fig, "q1_delivery_buckets")


def plot_q1_lateness(df: pd.DataFrame) -> Path:
    df = df.sort_values("vs_promised_date")
    labels = [s.split(") ", 1)[-1] for s in df["vs_promised_date"]]
    is_early = df["vs_promised_date"].str.contains("early|promised day")
    colors = [DIVERGING["low"] if e else DIVERGING["high"] for e in is_early]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.6))

    b1 = ax1.bar(labels, df["mean_review_score"], color=colors, width=0.62)
    _labels(ax1, b1, "{:.2f}")
    ax1.set_ylim(1, 5)
    ax1.set_ylabel("Mean review score (1-5)")
    ax1.set_title("Score vs the promise")

    b2 = ax2.bar(labels, df["pct_one_star"] * 100, color=colors, width=0.62)
    _labels(ax2, b2, "{:.0f}%")
    ax2.set_ylabel("Share of 1-star reviews")
    ax2.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax2.set_title("1-star share vs the promise")

    for ax in (ax1, ax2):
        plt.setp(ax.get_xticklabels(), rotation=25, ha="right")

    fig.suptitle("Q1  The promised delivery date is a cliff  ·  one day late ≈ minus one star")
    fig.tight_layout()
    return save_fig(fig, "q1_lateness")


# --------------------------------------------------------------------------- #
# Q2 - category delivery performance
# --------------------------------------------------------------------------- #
def plot_q2_category_late(df: pd.DataFrame, top: int = 12) -> Path:
    most_often = df.sort_values("pct_late", ascending=False).head(top).iloc[::-1]
    most_damage = df.sort_values("score_points_lost_total", ascending=False).head(top).iloc[::-1]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 6))

    b1 = ax1.barh(most_often["category"], most_often["pct_late"] * 100,
                  color=PRIMARY, height=0.66)
    _labels(ax1, b1, "{:.1f}%", horizontal=True)
    ax1.set_xlabel("Share of orders delivered after the promised date")
    ax1.xaxis.set_major_formatter(mtick.PercentFormatter())
    ax1.set_title("Most likely to break the promise")
    ax1.grid(axis="x")
    ax1.grid(axis="y", visible=False)

    b2 = ax2.barh(most_damage["category"], most_damage["score_points_lost_total"],
                  color=CATEGORICAL[1], height=0.66)
    _labels(ax2, b2, "{:.0f}", horizontal=True)
    ax2.set_xlabel("Total review points lost to lateness  (pct_late × score gap × orders)")
    ax2.set_title("Most total review damage (volume × rate)")
    ax2.grid(axis="x")
    ax2.grid(axis="y", visible=False)

    fig.suptitle("Q2  Worst-performing categories are not the highest-volume ones  ·  "
                 "every category still beats its estimate on average")
    fig.tight_layout()
    return save_fig(fig, "q2_category_late")


# --------------------------------------------------------------------------- #
# Q3 - repeat customers
# --------------------------------------------------------------------------- #
def plot_q3_repeat(df: pd.DataFrame, overall_rate: float) -> Path:
    df = df.copy()
    df["label"] = df["first_review_score"].map(
        lambda s: "no review" if pd.isna(s) else f"{int(s)}-star"
    )
    colors = [INK["muted"] if pd.isna(s) else PRIMARY for s in df["first_review_score"]]

    fig, ax = plt.subplots(figsize=(8.5, 4.8))
    bars = ax.bar(df["label"], df["pct_returned"] * 100, color=colors, width=0.6)
    _labels(ax, bars, "{:.1f}%")
    ax.axhline(overall_rate * 100, color=INK["secondary"], lw=1.2, ls="--")
    ax.annotate(f"overall repeat rate  {overall_rate*100:.1f}%",
                (-0.45, overall_rate * 100), xytext=(0, 5),
                textcoords="offset points", ha="left", fontsize=9,
                color=INK["secondary"])
    ax.set_ylim(0, max(df["pct_returned"] * 100) * 1.6)
    ax.set_ylabel("Customers who ever place a 2nd order")
    ax.set_xlabel("Review score left on the first order")
    ax.yaxis.set_major_formatter(mtick.PercentFormatter())
    ax.set_title("Q3  A bad first order barely moves the return rate — because almost nobody returns")
    fig.tight_layout()
    return save_fig(fig, "q3_repeat")


# --------------------------------------------------------------------------- #
# Q4 - seller segmentation
# --------------------------------------------------------------------------- #
def plot_q4_seller_segments(df_segments: pd.DataFrame) -> Path:
    """Segment-level chart from 04_seller_segmentation.sql (4 rows):
    x = reliability, y = review score, one labelled point per segment.
    GMV and seller counts are in the labels rather than a size channel -
    four segments do not need a third visual encoding."""
    d = df_segments.set_index("segment")
    color = {
        "Core - invest": PRIMARY,
        "Rising - grow": CATEGORICAL[2],
        "Steady - maintain": INK["muted"],
        "At risk - fix or drop": STATUS["critical"],
    }
    # (x-offset pt, y-offset pt, ha) hand-placed so labels never touch a marker
    label_pos = {
        "Rising - grow": (0, 34, "center"),
        "Core - invest": (16, 2, "left"),
        "Steady - maintain": (16, -20, "left"),
        "At risk - fix or drop": (-16, 0, "right"),
    }

    fig, ax = plt.subplots(figsize=(9.5, 6))
    for seg, row in d.iterrows():
        x, y = row["avg_pct_shipped_late"] * 100, row["avg_review_score"]
        ax.scatter(x, y, s=460, color=color.get(seg, INK["muted"]),
                   edgecolor=SURFACE, linewidth=1.5, zorder=3)
        dx, dy, ha = label_pos.get(seg, (10, 8, "left"))
        ax.annotate(
            f"{seg}\n{int(row['sellers']):,} sellers · {row['pct_of_gmv']:.0f}% of GMV",
            (x, y), xytext=(dx, dy), textcoords="offset points", ha=ha, va="center",
            fontsize=9.5, color=INK["primary"], weight="bold",
        )
    ax.axhline(4.0, color=INK["baseline"], lw=1, ls=":")
    ax.set_xlabel("Average share of orders shipped late to the carrier  (seller-controlled)")
    ax.set_ylabel("Average review score")
    ax.xaxis.set_major_formatter(mtick.PercentFormatter())
    ax.set_xlim(-6, 52)
    ax.set_ylim(2.5, 5)
    ax.set_title("Q4  The 'at-risk' segment: 27% of sellers, 13% of GMV — and a 2.96 review average")
    fig.tight_layout()
    return save_fig(fig, "q4_seller_segments")


# --------------------------------------------------------------------------- #
# Q5 - revenue seasonality
# --------------------------------------------------------------------------- #
def plot_q5_seasonality(df: pd.DataFrame) -> Path:
    d = df.copy()
    d["month"] = pd.to_datetime(d["month"])
    full = d[~d["is_partial_month"]]

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(10, 7), sharex=True)

    ax1.plot(full["month"], full["revenue"] / 1e6, color=PRIMARY, lw=2, marker="o", ms=4)
    ax1.set_ylabel("Revenue  (R$ millions)")
    ax1.set_ylim(0, None)
    ax1.set_title("Revenue: 8× growth through 2017, then flat for all of 2018")

    ax2.plot(full["month"], full["orders"], color=CATEGORICAL[1], lw=2, marker="o", ms=4)
    ax2.set_ylabel("Orders")
    ax2.set_ylim(0, None)
    ax2.set_xlabel("Month of purchase")
    ax2.set_title("Order volume, same shape")

    bf = pd.Timestamp("2017-11-01")
    for ax in (ax1, ax2):
        ax.axvline(bf, color=INK["muted"], lw=1, ls="--")
    ax1.annotate("Nov 2017\nBlack Friday", (bf, ax1.get_ylim()[1] * 0.92),
                 xytext=(8, 0), textcoords="offset points", fontsize=9,
                 color=INK["secondary"], va="top")

    fig.suptitle("Q5  Revenue & order seasonality  ·  Jan 2017 – Aug 2018 (partial months dropped)")
    fig.align_ylabels()
    fig.tight_layout()
    return save_fig(fig, "q5_seasonality")


# --------------------------------------------------------------------------- #
# Q6 - distance vs delay
# --------------------------------------------------------------------------- #
def plot_q6_distance(df_band: pd.DataFrame, df_state: pd.DataFrame) -> Path:
    band = df_band.sort_values("distance_band")
    xlab = [s.split(") ", 1)[-1] for s in band["distance_band"]]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 5.4))

    ax1.plot(xlab, band["avg_delivery_days"], color=PRIMARY, lw=2, marker="o",
             label="actual delivery time")
    ax1.plot(xlab, band["avg_days_vs_estimate"], color=CATEGORICAL[1], lw=2, marker="s",
             label="vs the promised date")
    ax1.plot(xlab, band["avg_seller_handover_days"], color=INK["muted"], lw=1.6,
             marker="^", ls="--", label="seller handover time")
    ax1.axhline(0, color=INK["baseline"], lw=1)
    ax1.set_ylabel("Days")
    ax1.set_xlabel("Seller → customer distance")
    ax1.set_title("Distance stretches transit time, not the promise gap")
    ax1.legend(frameon=False, fontsize=9)
    plt.setp(ax1.get_xticklabels(), rotation=20, ha="right")

    st = df_state[~df_state["low_sample"]].sort_values("pct_late", ascending=False).head(10).iloc[::-1]
    colors = [STATUS["critical"] if v >= 0.15 else PRIMARY for v in st["pct_late"]]
    b = ax2.barh(st["customer_state"], st["pct_late"] * 100, color=colors, height=0.66)
    _labels(ax2, b, "{:.0f}%", horizontal=True)
    ax2.set_xlabel("Share of orders delivered late")
    ax2.xaxis.set_major_formatter(mtick.PercentFormatter())
    ax2.set_title("The late states are mid-distance NE coast, not the far North")
    ax2.grid(axis="x")
    ax2.grid(axis="y", visible=False)

    fig.suptitle("Q6  Distance explains how long, not how late  ·  "
                 "r(distance, transit)=0.39  vs  r(distance, lateness)=−0.08")
    fig.tight_layout()
    return save_fig(fig, "q6_distance")
