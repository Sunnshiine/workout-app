from evidence_support import *  # noqa: F401,F403
from evidence_lane import *  # noqa: F401,F403


class AppCache(Lane):
    def entries(self):
        return sorted(p.name for p in self.cache.iterdir())

    def worktrees(self):
        return [line for line in self.git("worktree", "list", "--porcelain").splitlines() if line.startswith("worktree ")]

    def install_held_in_its_build(self, commit):
        install = subprocess.Popen([str(self.verify_path), "install", commit], cwd=str(self.checkout),
                                   env=self.environment({"STUB_BUILD_HOLD": "1"}), start_new_session=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        for _ in range(100):
            if (self.tmp / "building").exists() or install.poll() is not None:
                break
            time.sleep(0.1)
        return install

    def test_install_builds_a_commit_once_and_every_later_install_reuses_it(self):
        self.assertEqual(self.verify("install", self.a[:7]),
                         (0, self.cached_build(b"v1\n", self.a) + "\n", self.building(self.a)))
        self.assertEqual([call for call in self.calls() if call.startswith("xcodebuild")], [
            "xcodebuild build -project {c}/{a}.build/src/WorkoutTracker.xcodeproj -scheme WorkoutTracker "
            "-destination platform=iOS Simulator,id={sim} -derivedDataPath {c}/{a}.build/dd -skipPackagePluginValidation "
            "-skipMacroValidation CODE_SIGNING_ALLOWED=NO".format(c=self.cache, a=self.a, sim=self.sim)
            + cache_settings(self.tmp / "home")])
        self.assertEqual(self.entries(), [self.a, self.a + ".lock", "logs"],
                         "the abbreviated SHA keys the full one, and the scratch worktree and DerivedData are gone")
        self.assertEqual((self.cache / self.a / "WorkoutTracker.app" / "verify-stamp").read_text(),
                         "commit=%s\ndirty=0\norigin=cache\ncode_sha256=%s\n" % (self.a, bundle_hash(b"v1\n")))
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])
        self.assertEqual(self.verify("install", self.a), (0, self.cached_build(b"v1\n", self.a) + "\n", ""))
        self.assertEqual([call for call in self.calls() if call.startswith("xcodebuild")], [], "a hit builds nothing")

    def test_two_installs_of_one_commit_at_once_build_it_once(self):
        first = self.install_held_in_its_build(self.a)
        self.assertTrue((self.tmp / "building").exists(), "the first install never reached its build")
        waited = self.tmp / "second.err"
        with open(str(waited), "w") as err:
            second = subprocess.Popen([str(self.verify_path), "install", self.a], cwd=str(self.checkout),
                                      env=self.environment({"SIM": self.other_sim, "STUB_BUILD_HOLD": "1"}),
                                      start_new_session=True, stdout=subprocess.PIPE, stderr=err, universal_newlines=True)
        wait_line = "waiting for another build of %s into the app cache (lsof %s/%s.lock lists it)\n" % (
            self.a[:8], self.cache, self.a)
        for _ in range(100):
            if waited.read_text() == wait_line or second.poll() is not None:
                break
            time.sleep(0.1)
        (self.tmp / "release").touch()
        first_out, first_err = first.communicate(timeout=30)
        second_out, _ = second.communicate(timeout=30)
        self.assertEqual((first.returncode, first_out, first_err), (0, self.cached_build(b"v1\n", self.a) + "\n",
                                                                    self.building(self.a)))
        self.assertEqual((second.returncode, second_out, waited.read_text()),
                         (0, self.cached_build(b"v1\n", self.a) + "\n", wait_line))
        self.assertEqual(len([call for call in self.calls() if call.startswith("xcodebuild")]), 1)

    def test_a_failed_build_publishes_nothing_and_the_next_install_builds_it(self):
        self.assertEqual(self.verify("install", self.a, STUB_BUILD_FAIL="1"), (65, "", self.building(self.a) + (
            "error: stub compile error\n** BUILD FAILED **\nbuild log: {c}/logs/{a}.log\napp on {sim} unchanged: nothing "
            "installed; this install wanted {a8} from the app cache, and its build failed\n").format(
                c=self.cache, a=self.a, sim=self.sim, a8=self.a[:8])))
        self.assertEqual(self.entries(), [self.a + ".lock", "logs"], "no entry, no scratch")
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])
        self.assertEqual(self.verify("install", self.a), (0, self.cached_build(b"v1\n", self.a) + "\n", self.building(self.a)))

    def killed_build(self, commit):
        install = self.install_held_in_its_build(commit)
        self.addCleanup(install.communicate)
        self.assertTrue((self.tmp / "building").exists(), "the install never reached its build")
        os.killpg(install.pid, signal.SIGKILL)
        install.wait()
        (self.tmp / "building").unlink()
        self.assertEqual(self.entries(), [commit + ".build", commit + ".lock", "logs"])

    def test_another_commits_install_sweeps_a_killed_builds_scratch_and_worktree(self):
        self.killed_build(self.a)
        self.assertEqual(len(self.worktrees()), 2)
        self.assertEqual(self.verify("install", self.b)[0], 0)
        self.assertEqual(self.entries(), sorted([self.a + ".lock", self.b, self.b + ".lock", "logs"]))
        self.assertEqual(self.worktrees(), ["worktree %s" % self.checkout])

    def test_a_killed_installs_lock_frees_when_its_build_exits_though_git_leaves_processes_behind(self):
        real = [os.environ.get("GIT_CONFIG_GLOBAL") or os.path.expanduser("~/.gitconfig"),
                os.path.expanduser("~/.config/git/config")]
        hooks = self.tmp / "hooks"
        hooks.mkdir()
        (hooks / "post-checkout").write_text('#!/bin/sh\nsleep 60 >/dev/null 2>&1 &\necho $! >> "%s"\n'
                                             % (self.tmp / "hook-pids"))
        (hooks / "post-checkout").chmod(0o755)
        self.addCleanup(subprocess.run, ["sh", "-c", 'kill -9 $(cat "$0") 2>/dev/null', str(self.tmp / "hook-pids")])
        (self.tmp / "gitconfig").write_text("[include]\n%s[core]\n\tfsmonitor = true\n\thooksPath = %s\n"
                                            % ("".join("\tpath = %s\n" % path for path in real), hooks))
        (self.tmp / "bin" / "bash").symlink_to("/bin/bash")
        lock = self.cache / (self.a + ".lock")
        if shutil.which("lsof"):
            self.addCleanup(subprocess.run, ["sh", "-c", 'lsof -t "$0" | xargs kill -9', str(lock)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        install = self.install_held_in_its_build(self.a)
        self.addCleanup(install.communicate)
        self.assertTrue((self.tmp / "building").exists(), "the install never reached its build")
        os.kill(install.pid, signal.SIGKILL)
        (self.tmp / "release").touch()
        install.wait()
        after = subprocess.Popen([str(self.verify_path), "install", self.a], cwd=str(self.checkout),
                                 env=self.environment({}), start_new_session=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        try:
            out, _ = after.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            os.killpg(after.pid, signal.SIGKILL)
            after.communicate()
            self.fail("the next install still waits on the lock 20 s after the killed install's build exited")
        self.assertEqual((after.returncode, out), (0, self.cached_build(b"v1\n", self.a) + "\n"))

    def test_the_next_install_of_a_killed_builds_commit_builds_in_its_scratch(self):
        self.killed_build(self.a)
        kept = self.cache / (self.a + ".build") / "src" / "kept"
        kept.touch()
        install = self.install_held_in_its_build(self.a)
        self.assertTrue(kept.exists(), "the killed build's worktree and DerivedData are built on, not recreated")
        (self.tmp / "release").touch()
        out, _ = install.communicate(timeout=30)
        self.assertEqual((install.returncode, out), (0, self.cached_build(b"v1\n", self.a) + "\n"))
        self.assertEqual(self.entries(), [self.a, self.a + ".lock", "logs"])

    def test_a_commit_the_repo_does_not_know_is_refused_before_any_simulator(self):
        self.assertEqual(self.verify("install", "0badc0de"),
                         (2, "", "0badc0de names no single commit in this repo (unknown or ambiguous)\n"))
        self.assertEqual(self.calls(), [])


class EvidenceBase(Lane):
    def setUp(self):
        super().setUp()
        self.verify("build")

    def test_a_branchs_runs_land_in_the_main_checkout_under_the_branch_name(self):
        self.git("checkout", "-q", "-b", "lane/x+y")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b), lane="lane-x-y"), ""))

    def test_a_detached_worktrees_runs_land_under_its_directory_name(self):
        self.git("checkout", "-q", "--detach")
        self.assertEqual(self.verify("launch", "session", VERIFY_RUN="lane-1"),
                         (0, self.launched(self.worktree_build(b"v2\n", self.b), lane="detached-checkout"), ""))

    def test_verify_evidence_names_the_parent_of_the_run_directories(self):
        elsewhere = self.tmp / "elsewhere"
        code, out, err = self.verify("launch", "session", VERIFY_RUN="lane-1", VERIFY_EVIDENCE=str(elsewhere))
        self.assertEqual((code, out.splitlines()[-1], err), (0, "evidence %s/lane-1" % elsewhere, ""))

    def test_a_linked_worktrees_runs_land_in_the_main_checkout_so_they_outlive_it(self):
        linked = self.tmp / "linked"
        self.git("worktree", "add", "-q", "-b", "lane/linked", str(linked))
        verify = self.link_verify(linked)
        self.assertEqual(self.verify("diff", "01-before", "02-after-log", verify=verify, VERIFY_RUN="lane-1"), (1, "", (
            "no evidence directory for this run in %s; name one: VERIFY_RUN=<run> %s diff ...\nrecent runs:\n"
        ) % (self.checkout / ".claude" / "work" / "evidence" / "lane-linked", verify)))
