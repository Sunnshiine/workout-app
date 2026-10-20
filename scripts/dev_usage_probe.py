"""Reads the process table and exact CPU and memory figures for scripts/dev-usage.py.

Live calls the kernel through ctypes: proc_listallpids and proc_pidinfo for the table and a cwd,
KERN_PROCARGS2 for argv, proc_pid_rusage (RUSAGE_INFO_V4) for CPU and footprint, host_statistics
for host ticks. Fake reads the same answers from a JSON file, so tests run without real processes.
"""
from __future__ import annotations

import ctypes
import os

C = ctypes
U64 = C.c_uint64
U32 = C.c_uint32
PROC_PIDT_SHORTBSDINFO = 13
PROC_PIDVNODEPATHINFO = 9
VNODE_INFO_SIZE = 152
MAXPATHLEN = 1024
HOST_CPU_LOAD_INFO = 3
HOST_VM_INFO64 = 4


class ShortInfo(C.Structure):
    _fields_ = [("pid", U32), ("ppid", U32), ("pgid", U32), ("status", U32), ("comm", C.c_char * 16)] + [
        (n, U32) for n in ("flags", "uid", "gid", "ruid", "rgid", "svuid", "svgid", "rfu")]


class RusageV4(C.Structure):
    _fields_ = [("uuid", C.c_uint8 * 16)] + [(n, U64) for n in (
        "user", "system", "pkg_idle_wkups", "interrupt_wkups", "pageins", "wired_size", "resident_size",
        "phys_footprint", "proc_start_abstime", "proc_exit_abstime", "child_user", "child_system",
        "child_pkg_idle_wkups", "child_interrupt_wkups", "child_pageins", "child_elapsed_abstime",
        "diskio_bytesread", "diskio_byteswritten", "cpu_time_qos_default", "cpu_time_qos_maintenance",
        "cpu_time_qos_background", "cpu_time_qos_utility", "cpu_time_qos_legacy",
        "cpu_time_qos_user_initiated", "cpu_time_qos_user_interactive", "billed_system_time",
        "serviced_system_time", "logical_writes", "lifetime_max_phys_footprint", "instructions", "cycles",
        "billed_energy", "serviced_energy", "interval_max_phys_footprint", "runnable_time")]


class VmStats64(C.Structure):
    _fields_ = ([(n, U32) for n in ("free", "active", "inactive", "wire")]
                + [(n, U64) for n in ("zero_fill", "reactivations", "pageins", "pageouts", "faults",
                                      "cow_faults", "lookups", "hits", "purges")]
                + [(n, U32) for n in ("purgeable", "speculative")]
                + [(n, U64) for n in ("decompressions", "compressions", "swapins", "swapouts")]
                + [(n, U32) for n in ("compressor", "throttled", "external", "internal")]
                + [("uncompressed_in_compressor", U64)])


class Live:
    def __init__(self):
        lib = C.CDLL("/usr/lib/libSystem.B.dylib")
        lib.mach_host_self.restype = U32
        timebase = (U32 * 2)()
        lib.mach_timebase_info(timebase)
        self.lib = lib
        self.tick_s = timebase[0] / timebase[1] / 1e9
        self.args_buf = None

    def table(self) -> dict:
        lib = self.lib
        count = lib.proc_listallpids(None, 0)
        pids = (C.c_int * (count + 256))()
        count = lib.proc_listallpids(pids, C.sizeof(pids))
        info, size, table = ShortInfo(), C.sizeof(ShortInfo), {}
        for pid in pids[:count]:
            if lib.proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, C.byref(info), size) == size:
                table[pid] = (info.ppid, info.comm.decode(errors="replace"))
        return table

    def argv(self, pid: int) -> list:
        if self.args_buf is None:
            argmax, size = C.c_int(), C.c_size_t(4)
            self.lib.sysctlbyname(b"kern.argmax", C.byref(argmax), C.byref(size), None, 0)
            self.args_buf = C.create_string_buffer(argmax.value)
        mib, size = (C.c_int * 3)(1, 49, pid), C.c_size_t(len(self.args_buf))
        if self.lib.sysctl(mib, 3, self.args_buf, C.byref(size), None, 0) != 0 or size.value < 4:
            return []
        raw = C.string_at(self.args_buf, size.value)
        argc = int.from_bytes(raw[:4], "little")
        rest = raw[4:]
        start = rest.find(b"\0")
        while 0 <= start < len(rest) and rest[start] == 0:
            start += 1
        return [a.decode(errors="replace") for a in rest[start:].split(b"\0")[:argc]]

    def cwd(self, pid: int) -> str | None:
        buf = C.create_string_buffer(2 * (VNODE_INFO_SIZE + MAXPATHLEN))
        if self.lib.proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, buf, len(buf)) != len(buf):
            return None
        return buf.raw[VNODE_INFO_SIZE:VNODE_INFO_SIZE + MAXPATHLEN].split(b"\0")[0].decode(errors="replace")

    def rusage(self, pid: int) -> tuple | None:
        ru = RusageV4()
        if self.lib.proc_pid_rusage(pid, 4, C.byref(ru)) != 0:
            return None
        ticks = ru.user + ru.system + ru.child_user + ru.child_system
        return ticks * self.tick_s, ru.phys_footprint / 2**20

    def host(self) -> tuple:
        lib, port = self.lib, self.lib.mach_host_self()
        load, count = (U32 * 4)(), U32(4)
        lib.host_statistics(port, HOST_CPU_LOAD_INFO, load, C.byref(count))
        vm, count, page = VmStats64(), U32(C.sizeof(VmStats64) // 4), C.c_size_t()
        lib.host_statistics64(port, HOST_VM_INFO64, C.byref(vm), C.byref(count))
        lib.host_page_size(port, C.byref(page))
        boot, size = (C.c_long * 2)(), C.c_size_t(C.sizeof(C.c_long) * 2)
        lib.sysctlbyname(b"kern.boottime", boot, C.byref(size), None, 0)
        busy_s = (load[0] + load[1] + load[3]) / os.sysconf("SC_CLK_TCK")
        used_mb = (vm.internal - vm.purgeable + vm.wire + vm.compressor) * page.value / 2**20
        return busy_s, used_mb, boot[0]


class Fake:
    """A process table from JSON: {"host": [busy_s, used_mb, boot],
    "procs": {"<pid>": {"ppid", "comm", "argv", "cwd", "cpu", "mb"}}}."""

    def __init__(self, path: str):
        import json
        with open(path) as f:
            data = json.load(f)
        self.procs = {int(pid): p for pid, p in data["procs"].items()}
        self.host_row = tuple(data["host"])

    def table(self) -> dict:
        return {pid: (p["ppid"], p["comm"]) for pid, p in self.procs.items()}

    def argv(self, pid: int) -> list:
        return self.procs[pid].get("argv", [])

    def cwd(self, pid: int) -> str | None:
        return self.procs[pid].get("cwd")

    def rusage(self, pid: int) -> tuple | None:
        p = self.procs[pid]
        return (p["cpu"], p.get("mb", 0)) if "cpu" in p else None

    def host(self) -> tuple:
        return self.host_row


def probe():
    fake = os.environ.get("WORKOUT_DEV_USAGE_FAKE_PROCS")
    return Fake(fake) if fake else Live()
