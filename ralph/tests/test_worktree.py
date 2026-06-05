from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.worktree import (
    SECRETS_FILENAME,
    WorktreeError,
    WorktreeManager,
    default_git_runner,
)


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )


def _init_repo(repo: Path) -> None:
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "ralph@example.com")
    _git(repo, "config", "user.name", "Ralph")
    (repo / "README.md").write_text("seed\n")
    _git(repo, "add", "README.md")
    _git(repo, "commit", "-m", "seed")


class WorktreeLifecycleTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)
        self.manager = WorktreeManager(self.repo, runner=default_git_runner)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_create_makes_branch_worktree_off_base(self) -> None:
        wt_path = self.repo / ".worktrees" / "issue-1"
        worktree = self.manager.create(wt_path, "agent/issue-1", "main")

        self.assertTrue(wt_path.is_dir())
        self.assertTrue((wt_path / "README.md").is_file())
        self.assertEqual(worktree.branch, "agent/issue-1")
        self.assertFalse(worktree.secrets_copied)

        head = subprocess.run(
            ["git", "-C", str(wt_path), "rev-parse", "--abbrev-ref", "HEAD"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(head.stdout.strip(), "agent/issue-1")

    def test_create_replaces_stale_worktree(self) -> None:
        wt_path = self.repo / ".worktrees" / "issue-1"
        self.manager.create(wt_path, "agent/issue-1", "main")
        # Recreating the same branch/path must succeed (stale removed first).
        again = self.manager.create(wt_path, "agent/issue-1", "main")
        self.assertTrue(again.path.is_dir())

    def test_remove_and_prune_clear_worktree(self) -> None:
        wt_path = self.repo / ".worktrees" / "issue-1"
        self.manager.create(wt_path, "agent/issue-1", "main")
        self.manager.remove(wt_path, "agent/issue-1")
        listing = subprocess.run(
            ["git", "-C", str(self.repo), "worktree", "list", "--porcelain"],
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertNotIn("issue-1", listing.stdout)

    def test_remove_is_idempotent_for_missing_worktree(self) -> None:
        # Best-effort cleanup never raises on a path that was never created.
        self.manager.remove(self.repo / ".worktrees" / "ghost", "agent/ghost")

    def test_create_off_missing_ref_raises(self) -> None:
        with self.assertRaises(WorktreeError):
            self.manager.create(self.repo / ".worktrees" / "x", "agent/x", "no-such-ref")


class SecretsCopyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self._tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)
        self.dest = Path(self._tmp.name) / "dest"
        self.dest.mkdir()

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def test_configured_source_is_copied(self) -> None:
        source = Path(self._tmp.name) / "Secrets.xcconfig"
        source.write_text("KEY = value\n")
        manager = WorktreeManager(self.repo, secrets_source=str(source))

        copied = manager.copy_secrets(self.dest)

        self.assertTrue(copied)
        self.assertEqual((self.dest / SECRETS_FILENAME).read_text(), "KEY = value\n")

    def test_configured_missing_source_is_error(self) -> None:
        manager = WorktreeManager(self.repo, secrets_source=str(self.repo / "missing.xcconfig"))
        with self.assertRaises(WorktreeError):
            manager.copy_secrets(self.dest)

    def test_repo_root_fallback_is_copied(self) -> None:
        (self.repo / SECRETS_FILENAME).write_text("FROM = root\n")
        manager = WorktreeManager(self.repo, secrets_source="")

        copied = manager.copy_secrets(self.dest)

        self.assertTrue(copied)
        self.assertEqual((self.dest / SECRETS_FILENAME).read_text(), "FROM = root\n")

    def test_no_source_is_noop_success(self) -> None:
        manager = WorktreeManager(self.repo, secrets_source="")
        copied = manager.copy_secrets(self.dest)
        self.assertFalse(copied)
        self.assertFalse((self.dest / SECRETS_FILENAME).exists())

    def test_create_copies_secrets_into_new_worktree(self) -> None:
        (self.repo / SECRETS_FILENAME).write_text("FROM = root\n")
        manager = WorktreeManager(self.repo, secrets_source="")
        wt_path = self.repo / ".worktrees" / "issue-9"
        worktree = manager.create(wt_path, "agent/issue-9", "main")
        self.assertTrue(worktree.secrets_copied)
        self.assertEqual((wt_path / SECRETS_FILENAME).read_text(), "FROM = root\n")


if __name__ == "__main__":
    unittest.main()
