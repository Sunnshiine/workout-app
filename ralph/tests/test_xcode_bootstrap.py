from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = REPO_ROOT / "scripts" / "bootstrap-xcode-worktree.sh"
INSTALL = REPO_ROOT / "scripts" / "install-worktree-bootstrap.sh"
HOOK = REPO_ROOT / ".githooks" / "post-checkout"
SECRETS = "Secrets.xcconfig"
TEMPLATE = "Secrets.xcconfig.template"


def _run(
    args: list[str],
    *,
    cwd: Path,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    completed = subprocess.run(
        args,
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )
    if check and completed.returncode != 0:
        raise AssertionError(
            f"{args} failed with {completed.returncode}\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
    return completed


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return _run(["git", "-C", str(repo), *args], cwd=repo)


def _init_repo(repo: Path) -> None:
    repo.mkdir()
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "bootstrap@example.com")
    _git(repo, "config", "user.name", "Bootstrap")
    (repo / ".gitignore").write_text(f"{SECRETS}\n")
    (repo / "README.md").write_text("seed\n")
    (repo / TEMPLATE).write_text("GID_CLIENT_ID = TEMPLATE\n")
    _git(repo, "add", ".gitignore", "README.md", TEMPLATE)
    _git(repo, "commit", "-m", "seed")


def _clean_env(**updates: str) -> dict[str, str]:
    env = os.environ.copy()
    env.pop("SECRETS_XCCONFIG_SOURCE", None)
    env.update(updates)
    return env


def _copy_bootstrap_files(repo: Path) -> None:
    scripts = repo / "scripts"
    hooks = repo / ".githooks"
    scripts.mkdir(exist_ok=True)
    hooks.mkdir(exist_ok=True)
    shutil.copy2(BOOTSTRAP, scripts / BOOTSTRAP.name)
    shutil.copy2(INSTALL, scripts / INSTALL.name)
    shutil.copy2(HOOK, hooks / HOOK.name)
    for path in [
        scripts / BOOTSTRAP.name,
        scripts / INSTALL.name,
        hooks / HOOK.name,
    ]:
        path.chmod(0o755)
    _git(repo, "add", "scripts", ".githooks")
    _git(repo, "commit", "-m", "add bootstrap")


class XcodeBootstrapScriptTests(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def _repo(self, name: str = "repo") -> Path:
        repo = self.root / name
        _init_repo(repo)
        return repo

    def test_existing_destination_is_not_overwritten(self) -> None:
        repo = self._repo()
        (repo / SECRETS).write_text("EXISTING = 1\n")
        source = self.root / "source.xcconfig"
        source.write_text("NEW = 1\n")

        _run(
            [str(BOOTSTRAP), str(repo)],
            cwd=repo,
            env=_clean_env(SECRETS_XCCONFIG_SOURCE=str(source)),
        )

        self.assertEqual((repo / SECRETS).read_text(), "EXISTING = 1\n")

    def test_environment_source_precedes_git_config_and_main_worktree(self) -> None:
        repo = self._repo()
        env_source = self.root / "env.xcconfig"
        config_source = self.root / "config.xcconfig"
        env_source.write_text("FROM = env\n")
        config_source.write_text("FROM = config\n")
        (repo / SECRETS).write_text("FROM = main\n")
        worktree = self.root / "worktree"
        _git(repo, "worktree", "add", "--detach", str(worktree), "main")
        _git(repo, "config", "workout.secretsXcconfigSource", str(config_source))

        _run(
            [str(BOOTSTRAP), str(worktree)],
            cwd=repo,
            env=_clean_env(SECRETS_XCCONFIG_SOURCE=str(env_source)),
        )

        self.assertEqual((worktree / SECRETS).read_text(), "FROM = env\n")

    def test_invalid_git_config_source_fails_fast(self) -> None:
        repo = self._repo()
        missing = self.root / "missing.xcconfig"
        _git(repo, "config", "workout.secretsXcconfigSource", str(missing))

        completed = _run(
            [str(BOOTSTRAP), str(repo)],
            cwd=repo,
            env=_clean_env(),
            check=False,
        )

        self.assertNotEqual(completed.returncode, 0)
        self.assertIn("workout.secretsXcconfigSource", completed.stderr)
        self.assertFalse((repo / SECRETS).exists())

    def test_main_worktree_secret_is_used_before_template(self) -> None:
        repo = self._repo()
        (repo / SECRETS).write_text("FROM = main\n")
        worktree = self.root / "worktree"
        _git(repo, "worktree", "add", "--detach", str(worktree), "main")

        _run([str(BOOTSTRAP), str(worktree)], cwd=repo, env=_clean_env())

        self.assertEqual((worktree / SECRETS).read_text(), "FROM = main\n")

    def test_template_fallback_creates_build_only_config(self) -> None:
        repo = self._repo()

        completed = _run([str(BOOTSTRAP), str(repo)], cwd=repo, env=_clean_env())

        self.assertEqual((repo / SECRETS).read_text(), "GID_CLIENT_ID = TEMPLATE\n")
        self.assertIn("live Google auth is not configured", completed.stderr)

    def test_post_checkout_hook_bootstraps_git_worktree_add(self) -> None:
        repo = self._repo()
        _copy_bootstrap_files(repo)
        (repo / SECRETS).write_text("FROM = main\n")
        _git(repo, "config", "core.hooksPath", ".githooks")

        worktree = self.root / "hook-worktree"
        _git(repo, "worktree", "add", "-b", "hook-test", str(worktree), "main")

        self.assertEqual((worktree / SECRETS).read_text(), "FROM = main\n")

    def test_installer_sets_hook_path_and_backfills_existing_worktrees(self) -> None:
        repo = self._repo()
        _copy_bootstrap_files(repo)
        (repo / SECRETS).write_text("FROM = main\n")
        worktree = self.root / "existing-worktree"
        _git(repo, "worktree", "add", "--detach", str(worktree), "main")

        _run([str(repo / "scripts" / INSTALL.name)], cwd=repo, env=_clean_env())

        hooks_path = _git(repo, "config", "--get", "core.hooksPath").stdout.strip()
        self.assertEqual(hooks_path, ".githooks")
        self.assertEqual((worktree / SECRETS).read_text(), "FROM = main\n")


if __name__ == "__main__":
    unittest.main()
