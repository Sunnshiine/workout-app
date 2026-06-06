"""Tests for ralph/orchestrator/simulator_pool.py.

Covers:
- Acquisition of a free simulator from the pool
- Contention: two acquires only lease different UDIDs (or the second raises)
- Release: lease file is removed after the context manager exits
- Stale lease recovery: a lease file whose owner PID is dead is reclaimable
- Gate-command wiring: the leased UDID reaches _simulator_destination
- No-pool / explicit-simulator-id pass-through (existing PR #253 behavior)
"""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from typing import Generator
from unittest.mock import patch

from ralph.orchestrator.simulator_pool import (
    SimulatorLease,
    SimulatorPool,
    SimulatorPoolError,
)
from ralph.orchestrator.loop import _gate_specs, _simulator_destination


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _dead_pid() -> int:
    """Return a PID that is guaranteed not to be alive on this machine."""
    # PID 1 is always alive; start from a high number unlikely to be in use.
    # We search for a vacant slot rather than hardcoding one.
    import os

    candidate = 99998
    for _ in range(100):
        try:
            os.kill(candidate, 0)
        except ProcessLookupError:
            return candidate
        except PermissionError:
            # PID exists but we can't signal it — it is alive; skip
            pass
        candidate -= 1
    raise RuntimeError("could not find a dead PID for testing")


class AcquisitionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp()
        self._lease_dir = Path(self._tmp) / "leases"

    def _pool(self, udids: list[str]) -> SimulatorPool:
        return SimulatorPool(udids, lease_dir=self._lease_dir)

    def test_acquires_one_udid_from_pool(self) -> None:
        pool = self._pool(["UDID-1", "UDID-2"])
        with pool.acquire() as lease:
            self.assertIn(lease.udid, {"UDID-1", "UDID-2"})

    def test_lease_file_exists_during_context(self) -> None:
        pool = self._pool(["UDID-A"])
        with pool.acquire() as lease:
            self.assertTrue((self._lease_dir / f"{lease.udid}.lease").exists())

    def test_lease_file_removed_after_release(self) -> None:
        pool = self._pool(["UDID-A"])
        with pool.acquire() as lease:
            path = self._lease_dir / f"{lease.udid}.lease"
        self.assertFalse(path.exists())

    def test_lease_file_records_pid_hostname_and_timestamp(self) -> None:
        pool = self._pool(["UDID-X"])
        with pool.acquire() as lease:
            data = json.loads((self._lease_dir / f"{lease.udid}.lease").read_text())
        self.assertEqual(data["pid"], os.getpid())
        self.assertIn("hostname", data)
        self.assertIn("started_at", data)

    def test_empty_pool_raises_immediately(self) -> None:
        pool = self._pool([])
        with self.assertRaises(SimulatorPoolError):
            with pool.acquire():
                pass  # pragma: no cover

    def test_pool_raises_when_all_leases_taken_by_live_pid(self) -> None:
        # Simulate all UDIDs being leased by the *current* process (same PID),
        # which counts as alive.
        pool = self._pool(["UDID-1"])
        self._lease_dir.mkdir(parents=True, exist_ok=True)
        lease_path = self._lease_dir / "UDID-1.lease"
        lease_path.write_text(
            json.dumps({"pid": os.getpid(), "hostname": "host", "started_at": "now"}),
            encoding="utf-8",
        )
        with self.assertRaises(SimulatorPoolError):
            with pool.acquire():
                pass  # pragma: no cover


class ContentionTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp()
        self._lease_dir = Path(self._tmp) / "leases"

    def _pool(self, udids: list[str]) -> SimulatorPool:
        return SimulatorPool(udids, lease_dir=self._lease_dir)

    def test_two_sequential_acquires_get_same_udid_when_first_released(self) -> None:
        pool = self._pool(["UDID-1"])
        with pool.acquire() as first:
            first_udid = first.udid
        with pool.acquire() as second:
            second_udid = second.udid
        self.assertEqual(first_udid, second_udid)

    def test_concurrent_acquires_choose_different_udids(self) -> None:
        """Simulate two concurrent processes: acquire first, then acquire second
        while the first lease file still exists."""
        pool = self._pool(["UDID-A", "UDID-B"])
        with pool.acquire() as first:
            # While first is held, acquire second.
            with pool.acquire() as second:
                self.assertNotEqual(first.udid, second.udid)

    def test_concurrent_acquires_exhaust_pool_raises(self) -> None:
        """When both simulators are busy, a third acquire raises."""
        pool = self._pool(["UDID-1", "UDID-2"])
        with pool.acquire():
            with pool.acquire():
                with self.assertRaises(SimulatorPoolError):
                    with pool.acquire():
                        pass  # pragma: no cover


class StaleLeaseRecoveryTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.mkdtemp()
        self._lease_dir = Path(self._tmp) / "leases"
        self._lease_dir.mkdir(parents=True, exist_ok=True)

    def _pool(self, udids: list[str]) -> SimulatorPool:
        return SimulatorPool(udids, lease_dir=self._lease_dir)

    def _write_lease(self, udid: str, *, pid: int) -> Path:
        path = self._lease_dir / f"{udid}.lease"
        path.write_text(
            json.dumps({"pid": pid, "hostname": "testhost", "started_at": "2025-01-01T00:00:00"}),
            encoding="utf-8",
        )
        return path

    def test_stale_lease_from_dead_pid_is_reclaimed(self) -> None:
        dead = _dead_pid()
        self._write_lease("UDID-STALE", pid=dead)
        pool = self._pool(["UDID-STALE"])
        # Should succeed by reclaiming the stale lease.
        with pool.acquire() as lease:
            self.assertEqual(lease.udid, "UDID-STALE")

    def test_live_lease_is_not_reclaimed(self) -> None:
        self._write_lease("UDID-LIVE", pid=os.getpid())
        pool = self._pool(["UDID-LIVE"])
        with self.assertRaises(SimulatorPoolError):
            with pool.acquire():
                pass  # pragma: no cover

    def test_stale_lease_content_is_replaced_with_new_owner_info(self) -> None:
        dead = _dead_pid()
        self._write_lease("UDID-OLD", pid=dead)
        pool = self._pool(["UDID-OLD"])
        with pool.acquire() as lease:
            data = json.loads((self._lease_dir / "UDID-OLD.lease").read_text())
        self.assertEqual(data["pid"], os.getpid())
        _ = lease


class GateWiringTests(unittest.TestCase):
    """The leased UDID must reach _simulator_destination / _gate_specs."""

    def test_simulator_destination_uses_id_when_simulator_id_given(self) -> None:
        dest = _simulator_destination("iPhone 17 Pro", simulator_id="LEASED-UDID")
        self.assertEqual(dest, "platform=iOS Simulator,id=LEASED-UDID")

    def test_simulator_destination_falls_back_to_name_without_id(self) -> None:
        dest = _simulator_destination("iPhone 17 Pro", simulator_id=None)
        self.assertEqual(dest, "platform=iOS Simulator,name=iPhone 17 Pro")

    def test_gate_specs_contain_leased_udid_as_destination(self) -> None:
        specs = _gate_specs("iPhone 17 Pro", simulator_id="POOL-UDID-42")
        xcode_specs = [s for s in specs if s.command and s.command[0] == "xcodebuild"]
        self.assertTrue(len(xcode_specs) > 0, "expected at least one xcodebuild gate spec")
        for spec in xcode_specs:
            self.assertIn("platform=iOS Simulator,id=POOL-UDID-42", spec.command)

    def test_gate_specs_without_simulator_id_use_name_destination(self) -> None:
        specs = _gate_specs("iPhone 17 Pro", simulator_id=None)
        xcode_specs = [s for s in specs if s.command and s.command[0] == "xcodebuild"]
        self.assertTrue(len(xcode_specs) > 0)
        for spec in xcode_specs:
            self.assertIn("platform=iOS Simulator,name=iPhone 17 Pro", spec.command)


if __name__ == "__main__":
    unittest.main()
