"""Worktree management for the Python runner.

``WorktreeManager`` creates the isolated issue and integration worktrees Ralph
gates run inside, copies ``Secrets.xcconfig`` so Xcode gates can build, and tears
worktrees down again. Every git invocation flows through an injectable runner so
tests drive a real temporary git repository instead of the host checkout, and
nothing here ever pushes or touches ``main``.

The ``Secrets.xcconfig`` copy mirrors ``copy_secrets_xcconfig`` in
``ralph/ralph.sh`` exactly:

- ``SECRETS_XCCONFIG_SOURCE`` set and pointing at a file  -> copy it.
- ``SECRETS_XCCONFIG_SOURCE`` set but not a file          -> hard error.
- ``SECRETS_XCCONFIG_SOURCE`` unset, repo-root file exists -> copy it.
- otherwise                                                -> no-op success.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

SECRETS_FILENAME = "Secrets.xcconfig"
_SECRETS_SOURCE_ENV = "SECRETS_XCCONFIG_SOURCE"


@dataclass(frozen=True)
class GitResult:
    """Outcome of one git invocation run through the seam."""

    args: tuple[str, ...]
    returncode: int
    stdout: str = ""
    stderr: str = ""

    @property
    def ok(self) -> bool:
        return self.returncode == 0


# A git runner takes the argv that follows ``git`` and returns a ``GitResult``.
# Real use wraps ``subprocess.run``; tests inject a runner over a temp repo.
GitRunner = Callable[[Sequence[str]], GitResult]


def default_git_runner(args: Sequence[str]) -> GitResult:
    """Run ``git`` with ``args`` and capture its result (never raises on exit)."""

    completed = subprocess.run(  # noqa: S603 - args are fully controlled, never shell.
        ["git", *args],  # noqa: S607 - git resolved from PATH by design.
        capture_output=True,
        text=True,
        check=False,
    )
    return GitResult(
        args=tuple(args),
        returncode=completed.returncode,
        stdout=completed.stdout,
        stderr=completed.stderr,
    )


class WorktreeError(RuntimeError):
    """Raised when a worktree cannot be created or prepared."""


@dataclass(frozen=True)
class Worktree:
    """An isolated worktree created off a base ref."""

    path: Path
    branch: str
    base_ref: str
    secrets_copied: bool = False


class WorktreeManager:
    """Creates, prepares, and tears down git worktrees for gate runs.

    ``repo_root`` is the main checkout that owns the worktree list. ``runner``
    is the git seam; ``secrets_source`` overrides the ``SECRETS_XCCONFIG_SOURCE``
    environment lookup (used by tests). The repo-root ``Secrets.xcconfig``
    fallback is always read from ``repo_root``.
    """

    def __init__(
        self,
        repo_root: Path,
        *,
        runner: GitRunner | None = None,
        secrets_source: str | None = None,
    ) -> None:
        self._repo_root = Path(repo_root)
        self._runner = runner or default_git_runner
        # None means "fall back to the environment at copy time", matching the
        # shell, which reads SECRETS_XCCONFIG_SOURCE lazily.
        self._secrets_source = secrets_source

    def create(self, path: Path, branch: str, base_ref: str) -> Worktree:
        """Create a fresh ``branch`` worktree at ``path`` off ``base_ref``.

        Any stale worktree/branch with the same name is removed first so reruns
        start clean, matching the shell's remove/prune-before-add sequence. The
        ``Secrets.xcconfig`` copy runs after the worktree exists; a copy failure
        removes the half-built worktree and raises.
        """

        path = Path(path)
        self.remove(path, branch)
        add = self._git(["worktree", "add", "-b", branch, str(path), base_ref])
        if not add.ok:
            raise WorktreeError(
                f"could not create worktree {path} (branch {branch!r}) off "
                f"{base_ref!r}: {add.stderr.strip() or add.stdout.strip()}"
            )
        try:
            secrets_copied = self.copy_secrets(path)
        except WorktreeError:
            self.remove(path, branch)
            raise
        return Worktree(
            path=path,
            branch=branch,
            base_ref=base_ref,
            secrets_copied=secrets_copied,
        )

    def copy_secrets(self, destination: Path) -> bool:
        """Copy ``Secrets.xcconfig`` into ``destination``; return whether a file was copied.

        Mirrors ``copy_secrets_xcconfig``: a configured-but-missing source is a
        hard error, a missing repo-root file is a silent no-op, and a present
        source is copied to ``<destination>/Secrets.xcconfig``.
        """

        source = self._secrets_xcconfig_source()
        if source is None:
            return False
        try:
            shutil.copyfile(source, Path(destination) / SECRETS_FILENAME)
        except OSError as exc:
            raise WorktreeError(
                f"failed to copy {SECRETS_FILENAME} from {source} to {destination}: {exc}"
            ) from exc
        return True

    def remove(self, path: Path, branch: str | None = None) -> None:
        """Force-remove the ``path`` worktree, delete ``branch``, and prune.

        Every step is best-effort, matching the shell's ``|| true`` cleanup: a
        missing worktree or branch is not an error.
        """

        self._git(["worktree", "remove", "--force", str(path)], check=False)
        if branch:
            self._git(["branch", "-D", branch], check=False)
        self.prune()

    def prune(self) -> None:
        """Prune administrative worktree state for removed worktrees."""

        self._git(["worktree", "prune"], check=False)

    def _secrets_xcconfig_source(self) -> Path | None:
        configured = self._configured_secrets_source()
        if configured is not None:
            source = Path(configured)
            if source.is_file():
                return source
            raise WorktreeError(
                f"{_SECRETS_SOURCE_ENV} is set but does not point to a file: {configured}"
            )
        fallback = self._repo_root / SECRETS_FILENAME
        return fallback if fallback.is_file() else None

    def _configured_secrets_source(self) -> str | None:
        if self._secrets_source is not None:
            return self._secrets_source or None
        value = os.environ.get(_SECRETS_SOURCE_ENV)
        return value or None

    def _git(self, args: Sequence[str], *, check: bool = True) -> GitResult:
        # ``-C repo_root`` keeps every worktree operation rooted at the main
        # checkout, regardless of the process cwd.
        result = self._runner(["-C", str(self._repo_root), *args])
        if check and not result.ok:
            raise WorktreeError(
                f"git {' '.join(args)} failed (exit {result.returncode}): "
                f"{result.stderr.strip() or result.stdout.strip()}"
            )
        return result
