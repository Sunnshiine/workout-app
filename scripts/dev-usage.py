#!/usr/bin/env python3
"""Usage: scripts/dev-usage.sh sample | record <name> [--sim UDID] -- <command...>
       scripts/dev-usage.sh report [--since DUR] [--by agent|sim|command]
       scripts/dev-usage.sh install | uninstall
Meters exact CPU seconds and memory per agent, per simulator, and per metered command, from
proc_pid_rusage, which counts every reaped child into its parent. Nothing is sampled from ps.

sample appends one row per agent, per booted simulator, and one for the host to
samples-<UTC date>.tsv: ts kind key pid cpu_s footprint_mb. An agent is a process whose argv[0]
is claude or codex with no agent above it; its key is the git worktree holding its cwd, and its
cpu_s is the CPU its process tree has used since it started. A simulator is a launchd_sim, keyed by
its device name. The host row's cpu_s is busy CPU since boot and footprint_mb is memory in use.
sample deletes sample files older than 30 days.

record runs the command and appends to commands.tsv: ts worktree name exit wall_s cpu_s max_rss_mb
sim sim_cpu_s load1. cpu_s is the command and every child it reaped; with --sim, sim_cpu_s is what
that simulator's launchd_sim tree used meanwhile. It passes stdin, stdout, stderr, and the exit
status through, forwards TERM, HUP, USR1, and USR2 to the command, and leaves INT and QUIT to the
terminal, which sends them to both. It says nothing unless the ledger write fails, and that never
changes the exit status. It exits 127 when the command is not found, 126 when it cannot run.

report prints the CPU seconds each agent, simulator, and the rest of the host used over --since
(default 24h; s, m, h, or d), with cores (CPU s per second of the window), share of host busy CPU,
and peak footprint. A key's CPU is, per pid, its last sample minus its first in the window, plus
the first when that pid was missing from an earlier sample in the window (it started after it).
--by command prints count, failures, median and p90 CPU s, median wall s, peak RSS, and median
simulator CPU s per command name.

install copies these scripts into the ledger directory and loads a user LaunchAgent that runs
sample every 60 s; uninstall unloads and deletes it and keeps the ledger. Nothing else installs it.
The ledger is ~/Library/Logs/WorkoutTracker/dev-usage, or WORKOUT_DEV_USAGE_DIR.
Exits 0, or 2 on a usage error.
"""
from __future__ import annotations

import _signal as signal  # not signal, which imports enum: a third of record's 50 ms budget
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

AGENTS = ("claude", "codex")
SAMPLE_COLUMNS = "ts\tkind\tkey\tpid\tcpu_s\tfootprint_mb"
COMMAND_COLUMNS = "ts\tworktree\tname\texit\twall_s\tcpu_s\tmax_rss_mb\tsim\tsim_cpu_s\tload1"
KEEP_DAYS = 30
FORWARDED = (signal.SIGTERM, signal.SIGHUP, signal.SIGUSR1, signal.SIGUSR2)
LEFT_TO_TERMINAL = (signal.SIGINT, signal.SIGQUIT)
LABEL = "com.sunnypatel.WorkoutTracker.dev-usage"
SCRIPTS = ("dev-usage.py", "dev_usage_probe.py", "dev_usage_report.py")
PYTHON = "/usr/bin/python3"


def ledger() -> str:
    return os.environ.get("WORKOUT_DEV_USAGE_DIR") or os.path.expanduser("~/Library/Logs/WorkoutTracker/dev-usage")


def usage(message: str = "") -> None:
    if message:
        print(f"dev-usage: {message}", file=sys.stderr)
    print(__doc__.split("\n\n")[0], file=sys.stderr)
    sys.exit(2)


def field(value) -> str:
    return str(value).replace("\t", " ").replace("\n", " ")


def append(path: str, header: str, rows: list) -> None:
    """One write() per call, so rows from concurrent writers never interleave."""
    body = "".join("\t".join(field(v) for v in row) + "\n" for row in rows).encode()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    try:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_EXCL, 0o644)
        body = (header + "\n").encode() + body
    except FileExistsError:
        fd = os.open(path, os.O_WRONLY | os.O_APPEND)
    try:
        os.write(fd, body)
    finally:
        os.close(fd)


def worktree(path: str | None) -> str:
    if not path:
        return "?"
    d = path
    while d != "/":
        if os.path.exists(os.path.join(d, ".git")):
            return d
        d = os.path.dirname(d)
    return path


def roots(p, table: dict, udid: str | None = None) -> dict:
    """Agent and simulator roots: pid -> ("agent",) or ("sim", device dir, udid)."""
    found = {}
    for pid, (_, comm) in table.items():
        if comm == "launchd_sim":
            device = sim_device(p.argv(pid))
            if device and udid in (None, device[1]):
                found[pid] = ("sim",) + device
        elif udid is None and (comm in AGENTS or is_version(comm)):
            argv = p.argv(pid)
            if argv and os.path.basename(argv[0]) in AGENTS:
                found[pid] = ("agent",)
    for pid in [pid for pid, r in found.items() if r[0] == "agent"]:
        up, seen = table[pid][0], set()
        while up in table and up > 1 and up not in seen:
            if up in found and found[up][0] == "agent":
                del found[pid]
                break
            seen.add(up)
            up = table[up][0]
    return found


def tree_usage(p, table: dict, found: dict) -> dict:
    """root pid -> [cpu_s, footprint_mb] summed over the live processes under it."""
    owner, totals = {}, {pid: [0.0, 0.0] for pid in found}
    for pid in table:
        path, up = [], pid
        while up not in owner:
            path.append(up)
            if up in found:
                owner[up] = up
                break
            parent = table.get(up, (0,))[0]
            if up <= 1 or parent not in table or parent == up:
                owner[up] = None
                break
            up = parent
        for q in path:
            owner[q] = owner[up]
        root = owner[pid]
        if root is not None:
            u = p.rusage(pid)
            if u:
                totals[root][0] += u[0]
                totals[root][1] += u[1]
    return totals


def is_version(comm: str) -> bool:
    """Claude Code's native binary is named for its version, so its comm reads 2.1.303."""
    parts = comm.split(".")
    return len(parts) == 3 and all(part.isdigit() for part in parts)


def sim_device(argv: list) -> tuple | None:
    """(device dir, udid) from launchd_sim .../Devices/<UDID>/data/var/run/launchd_bootstrap.plist."""
    if len(argv) < 2 or argv[0] != "launchd_sim" or "/Devices/" not in argv[1]:
        return None
    head, _, tail = argv[1].rpartition("/Devices/")
    udid = tail.split("/")[0]
    if len(udid) != 36 or udid.strip("0123456789ABCDEF-"):
        return None
    return f"{head}/Devices/{udid}", udid


def device_name(device_dir: str, udid: str) -> str:
    """The name in the device's XML device.plist, read without plistlib, which costs 30 ms to import."""
    try:
        with open(os.path.join(device_dir, "device.plist"), encoding="utf-8") as f:
            text = f.read()
    except (OSError, ValueError):
        return udid
    _, key, rest = text.partition("<key>name</key>")
    value = rest.split("<string>", 1)[-1].split("</string>", 1)[0] if key else ""
    if not value or "<" in value:
        return udid
    return value.replace("&lt;", "<").replace("&gt;", ">").replace("&amp;", "&")


def sample() -> None:
    from dev_usage_probe import probe
    p, now = probe(), int(time.time())
    table = p.table()
    found = roots(p, table)
    busy_s, used_mb, boot = p.host()
    rows = [(now, "host", "host", boot, f"{busy_s:.2f}", f"{used_mb:.0f}")]
    for pid, (cpu, mb) in sorted(tree_usage(p, table, found).items()):
        r = found[pid]
        key = worktree(p.cwd(pid)) if r[0] == "agent" else device_name(r[1], r[2])
        rows.append((now, r[0], key, pid, f"{cpu:.2f}", f"{mb:.0f}"))
    d = ledger()
    append(os.path.join(d, time.strftime("samples-%Y-%m-%d.tsv", time.gmtime(now))), SAMPLE_COLUMNS, rows)
    oldest = time.strftime("samples-%Y-%m-%d.tsv", time.gmtime(now - KEEP_DAYS * 86400))
    for name in os.listdir(d):
        if name.startswith("samples-") and name < oldest:
            os.remove(os.path.join(d, name))


def sim_cpu(udid: str | None) -> float | None:
    if not udid:
        return None
    try:
        from dev_usage_probe import probe
        p = probe()
        table = p.table()
        found = roots(p, table, udid)
        return sum(cpu for cpu, _ in tree_usage(p, table, found).values()) if found else None
    except Exception:  # noqa: BLE001 - metering must never stop the command
        return None


def record(args: list) -> None:
    if "--" not in args or args.index("--") == 0:
        usage("record needs a name, then -- and the command")
    split = args.index("--")
    name, options, command = args[0], args[1:split], args[split + 1:]
    sim = None
    if options[:1] == ["--sim"] and len(options) == 2:
        sim = options[1]
    elif options:
        usage(f"record takes only --sim UDID before --, not {' '.join(options)}")
    if not command:
        usage("record needs a command after --")

    child, pending = None, []

    def forward(signum, _frame):
        if child is None:
            pending.append(signum)
        else:
            os.kill(child, signum)

    for signum in FORWARDED + LEFT_TO_TERMINAL:
        if signal.getsignal(signum) != signal.SIG_IGN:
            signal.signal(signum, forward if signum in FORWARDED else lambda *_: None)
    sim_before = sim_cpu(sim)
    start = time.time()
    try:
        child = os.posix_spawnp(command[0], command, os.environ, setsigdef=(signal.SIGPIPE, signal.SIGXFSZ))
    except FileNotFoundError:
        print(f"dev-usage: {command[0]}: command not found", file=sys.stderr)
        sys.exit(127)
    except OSError as e:
        print(f"dev-usage: {command[0]}: {e.strerror}", file=sys.stderr)
        sys.exit(126)
    for signum in pending:
        os.kill(child, signum)
    _, status, ru = os.wait4(child, 0)
    wall = time.time() - start
    code = 128 + os.WTERMSIG(status) if os.WIFSIGNALED(status) else os.WEXITSTATUS(status)
    sim_after = sim_cpu(sim)
    sim_used = f"{sim_after - (sim_before or 0):.2f}" if sim_after is not None else "-"
    try:
        append(os.path.join(ledger(), "commands.tsv"), COMMAND_COLUMNS, [(
            int(start), worktree(os.getcwd()), name, code, f"{wall:.2f}", f"{ru.ru_utime + ru.ru_stime:.2f}",
            f"{ru.ru_maxrss / 2**20:.0f}", sim or "-", sim_used, f"{os.getloadavg()[0]:.2f}")])
    except Exception as e:  # noqa: BLE001 - a broken ledger must never change the command's result
        print(f"dev-usage: could not append to {ledger()}/commands.tsv: {e}", file=sys.stderr)
    if os.WIFSIGNALED(status):
        import resource
        signum = os.WTERMSIG(status)
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        signal.signal(signum, signal.SIG_DFL)
        os.kill(os.getpid(), signum)
    sys.exit(code)


def agent_label() -> str:
    return os.environ.get("WORKOUT_DEV_USAGE_LABEL", LABEL)


def agent_plist() -> str:
    return os.path.expanduser(f"~/Library/LaunchAgents/{agent_label()}.plist")


def launchctl(*args: str):
    import subprocess
    return subprocess.run(["launchctl", *args], capture_output=True, text=True)


def install() -> None:
    import plistlib
    import shutil
    d, label, plist = ledger(), agent_label(), agent_plist()
    here, copy = os.path.dirname(os.path.abspath(__file__)), os.path.join(ledger(), "bin")
    os.makedirs(copy, exist_ok=True)
    for name in SCRIPTS:
        shutil.copy2(os.path.join(here, name), copy)
    program = [PYTHON, "-I", "-S", os.path.join(copy, "dev-usage.py"), "sample"]
    os.makedirs(os.path.dirname(plist), exist_ok=True)
    with open(plist, "wb") as f:
        plistlib.dump({"Label": label, "ProgramArguments": program, "StartInterval": 60, "RunAtLoad": True,
                       "ProcessType": "Standard", "EnvironmentVariables": {"WORKOUT_DEV_USAGE_DIR": d},
                       "StandardErrorPath": os.path.join(d, "sample.err")}, f)
    domain = f"gui/{os.getuid()}"
    launchctl("bootout", f"{domain}/{label}")
    loaded = launchctl("bootstrap", domain, plist)
    if loaded.returncode:
        print(f"dev-usage: launchctl bootstrap {domain} {plist} failed: {loaded.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    print(f"installed the LaunchAgent {label}: {plist}\n"
          f"it runs {' '.join(program)} every 60 s, appending to {d}\n"
          f"scripts/dev-usage.sh uninstall removes it")


def uninstall() -> None:
    import shutil
    label, plist = agent_label(), agent_plist()
    launchctl("bootout", f"gui/{os.getuid()}/{label}")
    if not os.path.exists(plist):
        print(f"no LaunchAgent {label} is installed ({plist})")
        return
    os.remove(plist)
    shutil.rmtree(os.path.join(ledger(), "bin"), ignore_errors=True)
    print(f"removed the LaunchAgent {label} ({plist}); the ledger stays in {ledger()}")


def main(argv: list) -> None:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__, end="")
        sys.exit(0 if argv else 2)
    command, rest = argv[0], argv[1:]
    if command == "sample" and not rest:
        sample()
    elif command == "record" and rest:
        record(rest)
    elif command == "report":
        from dev_usage_report import report
        report(rest, ledger(), usage)
    elif command == "install" and not rest:
        install()
    elif command == "uninstall" and not rest:
        uninstall()
    else:
        usage(f"unknown command: {' '.join(argv)}")


if __name__ == "__main__":
    main(sys.argv[1:])
