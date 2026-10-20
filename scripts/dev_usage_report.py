"""The report subcommand of scripts/dev-usage.py: reads the ledger's TSVs over a window."""
from __future__ import annotations

import math
import os
import re
import statistics
import time

UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}
VIEWS = ("agent", "sim", "command")


def parse(args: list, usage) -> tuple:
    since, view, i = 86400, None, 0
    while i < len(args):
        flag, value = args[i], args[i + 1] if i + 1 < len(args) else ""
        m = re.fullmatch(r"(\d+)([smhd])", value)
        if flag == "--since" and m:
            since = int(m.group(1)) * UNITS[m.group(2)]
        elif flag == "--by" and value in VIEWS:
            view = value
        else:
            usage(f"report takes --since <N>s|m|h|d and --by agent|sim|command, not {' '.join(args[i:i + 2])}")
        i += 2
    return since, view


def rows(path: str, start: int) -> list:
    try:
        with open(path) as f:
            lines = [line.rstrip("\n").split("\t") for line in f]
    except FileNotFoundError:
        return []
    return [r for r in lines if r[0].isdigit() and int(r[0]) >= start]


def window_usage(samples: list) -> tuple:
    """Sample ticks and {(kind, key): [cpu_s, peak_mb]} over the window.

    Per pid, CPU is the last sample minus the first, plus the first when the pid was absent from an
    earlier tick of the window, since then all of it was used after that tick."""
    samples.sort(key=lambda r: int(r[0]))
    ticks = sorted({int(r[0]) for r in samples if r[1] == "host"})
    series, born = {}, {}
    for ts, kind, key, pid, cpu, mb in samples:
        s = series.get((kind, key, pid))
        if s is None:
            series[(kind, key, pid)] = [int(ts), float(cpu), float(cpu), float(mb)]
        else:
            s[2], s[3] = float(cpu), max(s[3], float(mb))
        born.setdefault((kind, pid), int(ts))
    totals = {}
    for (kind, key, pid), (first_ts, first, last, peak) in series.items():
        used = max(0.0, last - first)
        if ticks and first_ts == born[(kind, pid)] > ticks[0]:
            used += first
        t = totals.setdefault((kind, key), [0.0, 0.0])
        t[0] += used
        t[1] = max(t[1], peak)
    return ticks, totals


def clock(ts: int) -> str:
    return time.strftime("%Y-%m-%d %H:%M", time.localtime(ts))


def print_usage(ledger: str, start: int, view: str | None) -> None:
    first_file = time.strftime("samples-%Y-%m-%d.tsv", time.gmtime(start))
    names = sorted(n for n in os.listdir(ledger) if n.startswith("samples-") and n >= first_file) \
        if os.path.isdir(ledger) else []
    samples = [r for n in names for r in rows(os.path.join(ledger, n), start) if len(r) == 6]
    ticks, totals = window_usage(samples)
    if not ticks:
        print(f"no samples in {ledger} since {clock(start)}; scripts/dev-usage.sh install samples every 60 s")
        return
    span = ticks[-1] - ticks[0]
    host = sum(cpu for (kind, _), (cpu, _) in totals.items() if kind == "host")
    print(f"{clock(ticks[0])} .. {clock(ticks[-1])}: {span / 3600:.1f} h, {len(ticks)} samples, {ledger}")
    print(f"{'kind':<6} {'cpu_s':>10} {'cores':>6} {'share':>6} {'peak_mb':>8}  key")

    def line(kind, cpu, peak, key):
        cores = f"{cpu / span:.2f}" if span else "-"
        share = f"{100 * cpu / host:.0f}%" if host else "-"
        print(f"{kind:<6} {cpu:>10.1f} {cores:>6} {share:>6} {peak:>8}  {key}")

    kinds = (view,) if view else ("host", "agent", "sim")
    for kind in kinds:
        for (k, key), (cpu, peak) in sorted(totals.items(), key=lambda kv: -kv[1][0]):
            if k == kind:
                line(kind, cpu, f"{peak:.0f}", key)
    if not view:
        rest = host - sum(cpu for (kind, _), (cpu, _) in totals.items() if kind != "host")
        line("rest", rest, "-", "host busy CPU outside every agent and simulator tree")


def print_commands(ledger: str, start: int) -> None:
    runs = {}
    for r in rows(os.path.join(ledger, "commands.tsv"), start):
        if len(r) == 10:
            runs.setdefault(r[2], []).append(r)
    if not runs:
        print(f"no metered commands in {ledger} since {clock(start)}")
        return

    def p90(values):
        return sorted(values)[math.ceil(0.9 * len(values)) - 1]

    print(f"{'count':>5} {'failed':>6} {'cpu_med':>8} {'cpu_p90':>8} {'wall_med':>8} {'rss_peak':>8} {'sim_med':>8}  name")
    by_cpu = sorted(runs.items(), key=lambda kv: -sum(float(r[5]) for r in kv[1]))
    for name, rs in by_cpu:
        cpu = [float(r[5]) for r in rs]
        sim = [float(r[8]) for r in rs if r[8] != "-"]
        sim_med = f"{statistics.median(sim):.1f}" if sim else "-"
        print(f"{len(rs):>5} {sum(r[3] != '0' for r in rs):>6} {statistics.median(cpu):>8.1f} {p90(cpu):>8.1f} "
              f"{statistics.median(float(r[4]) for r in rs):>8.1f} {max(int(r[6]) for r in rs):>8} {sim_med:>8}  {name}")


def report(args: list, ledger: str, usage) -> None:
    since, view = parse(args, usage)
    start = int(time.time()) - since
    if view == "command":
        print_commands(ledger, start)
    else:
        print_usage(ledger, start, view)
