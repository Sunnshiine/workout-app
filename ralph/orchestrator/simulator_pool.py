"""Simulator pool leasing for concurrent Ralph runs.

Provides mutual exclusion across processes: each Ralph run that needs a simulator
for UI gates acquires an exclusive lease from a configured pool of UDIDs. The
lease is backed by a file in a lease directory; atomic ``O_CREAT|O_EXCL`` open
gives first-writer-wins semantics across processes.

Lease lifecycle
---------------
1. ``SimulatorPool.acquire()`` is a context manager.
2. It iterates the pool UDIDs in order, trying to create ``<lease_dir>/<udid>.lease``
   atomically. The first UDID whose file it can create (or reclaim from a stale
   dead-PID lease) is returned as the active ``SimulatorLease``.
3. The lease file records ``{"pid": ..., "hostname": ..., "started_at": ...}`` so
   any later process can detect staleness.
4. On context-manager exit (including exceptions) the lease file is deleted.

Stale lease recovery
--------------------
If a lease file exists but the owner PID is no longer alive (``os.kill(pid, 0)``
raises ``ProcessLookupError``), the file is atomically replaced with the new
owner's info.

If ``--simulator-id`` is explicitly given on the CLI, this module is not used;
the explicit UDID is passed through unchanged (PR #253 behaviour).
"""

from __future__ import annotations

import json
import os
import socket
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Generator


class SimulatorPoolError(RuntimeError):
    """Raised when no simulator can be leased from the pool."""


@dataclass(frozen=True)
class SimulatorLease:
    """An acquired, exclusive simulator lease."""

    udid: str
    lease_path: Path


def _pid_is_alive(pid: int) -> bool:
    """Return True if *pid* is a running process on this machine."""
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        # PID exists but we cannot signal it (different user) — treat as alive.
        return True


def _read_lease_pid(path: Path) -> int | None:
    """Return the PID recorded in a lease file, or None if unreadable/malformed."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return int(data["pid"])
    except Exception:
        return None


def _write_lease(path: Path) -> None:
    """Write owner information into *path*, creating it (overwriting if present)."""
    info = {
        "pid": os.getpid(),
        "hostname": socket.gethostname(),
        "started_at": datetime.now(tz=timezone.utc).isoformat(),
    }
    path.write_text(json.dumps(info), encoding="utf-8")


def _try_acquire_udid(udid: str, lease_dir: Path) -> SimulatorLease | None:
    """Try to acquire an exclusive lease for *udid*.

    Returns a ``SimulatorLease`` on success, ``None`` if the UDID is already
    leased by a live process.
    """
    lease_dir.mkdir(parents=True, exist_ok=True)
    lease_path = lease_dir / f"{udid}.lease"

    # Attempt atomic exclusive create (O_CREAT | O_EXCL).
    try:
        fd = os.open(str(lease_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        os.close(fd)
        # We own the newly created file; write our info into it.
        _write_lease(lease_path)
        return SimulatorLease(udid=udid, lease_path=lease_path)
    except FileExistsError:
        pass

    # File already exists — check for stale lease.
    owner_pid = _read_lease_pid(lease_path)
    if owner_pid is None or not _pid_is_alive(owner_pid):
        # Stale: overwrite with our info and take the lease.
        _write_lease(lease_path)
        return SimulatorLease(udid=udid, lease_path=lease_path)

    # Live owner — cannot acquire.
    return None


class SimulatorPool:
    """A pool of simulator UDIDs from which one can be leased at a time per process.

    Parameters
    ----------
    udids:
        Ordered list of simulator UDIDs in the pool.
    lease_dir:
        Directory where lease files are written.  Defaults to
        ``~/.ralph/simulator-leases`` but should always be set explicitly in
        production (via config or env) so operators control placement.
    """

    def __init__(self, udids: list[str], *, lease_dir: Path) -> None:
        self._udids = list(udids)
        self._lease_dir = lease_dir

    @contextmanager
    def acquire(self) -> Generator[SimulatorLease, None, None]:
        """Acquire one simulator from the pool for the duration of the block.

        Raises ``SimulatorPoolError`` if the pool is empty or all UDIDs are
        currently leased by live processes.
        """
        if not self._udids:
            raise SimulatorPoolError(
                "Simulator pool is empty. Configure --simulator-pool with at least one UDID."
            )

        lease: SimulatorLease | None = None
        for udid in self._udids:
            lease = _try_acquire_udid(udid, self._lease_dir)
            if lease is not None:
                break

        if lease is None:
            raise SimulatorPoolError(
                f"All {len(self._udids)} simulator(s) in the pool are currently leased. "
                "Wait for another Ralph process to finish or add more simulators to the pool."
            )

        try:
            yield lease
        finally:
            try:
                lease.lease_path.unlink(missing_ok=True)
            except OSError:
                pass
