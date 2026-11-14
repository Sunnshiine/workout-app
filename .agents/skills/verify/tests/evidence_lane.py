from evidence_support import *  # noqa: F401,F403


def bundle_hash(code):
    manifest = "%s  ./WorkoutTracker.debug.dylib\n" % hashlib.sha256(code).hexdigest()
    return hashlib.sha256(manifest.encode()).hexdigest()


def digest(code):
    return bundle_hash(code)[:12]


def built_app(home, code):
    derived = home / "Library" / "Developer" / "Xcode" / "DerivedData" / "WorkoutTracker-test"
    app = derived / "Build" / "Products" / "Debug-iphonesimulator" / "WorkoutTracker.app"
    app.mkdir(parents=True)
    (app / "WorkoutTracker.debug.dylib").write_bytes(code)
    (derived / "info.plist").touch()
    return app


def fake_checkout(root):
    checkout = root / "checkout"
    link_checkout(checkout)
    return checkout


FIXTURE_APP = [sys.executable, "-c", "import time; time.sleep(60)", "-UITEST_FIXTURE"]


SYSCTL_REFUSING_ALL_BUT_THE_SUITES_KNOBS = """#!/bin/sh
[ "$2" = kern.memorystatus_level ] && echo 5 || echo '{ 500.00 500.00 500.00 }'
"""

FOREGROUND_STUB = """import os, sys
with open("{dir}/foreground-calls", "a+") as calls:
    calls.write("probe\\n")
    calls.seek(0)
    probes = len(calls.read().splitlines())
answers = os.environ.get("STUB_FOREGROUND", "ok 1.02").split(",")
state, ratio = answers[min(probes, len(answers)) - 1].split()
print("%s (wall/cpu %s)" % (state, ratio))
sys.exit({"ok": 0, "starved": 3}.get(state, 1))
"""

LANE_STUB = """#!/bin/sh
tool=$(basename "$0")
printf '%s\\n' "$tool $*" >> "{dir}/calls"
case "$tool $1 $2" in
  "plutil -extract WorkspacePath") echo "{project}" ;;
  "xcrun simctl install")
    [ -z "${STUB_INSTALL_FAIL:-}" ] || exit 1
    [ -z "${STUB_STALE_INSTALL:-}" ] || [ ! -d "{dir}/containers/$3/WorkoutTracker.app" ] || exit 0
    rm -rf "{dir}/containers/$3"
    mkdir -p "{dir}/containers/$3"
    cp -R "$4" "{dir}/containers/$3/"
    [ -z "${STUB_TAMPER:-}" ] || printf x >> "{dir}/containers/$3/WorkoutTracker.app/WorkoutTracker.debug.dylib" ;;
  "xcrun simctl uninstall") rm -rf "{dir}/containers/$3" ;;
  "xcrun simctl get_app_container")
    [ -d "{dir}/containers/$3/WorkoutTracker.app" ] || exit 1
    echo "{dir}/containers/$3/WorkoutTracker.app" ;;
  "xcrun simctl bootstatus") exit "${STUB_BOOTSTATUS:-0}" ;;
  "xcrun simctl list") echo "    lane ({sim}) (Booted)" ;;
  "xcrun simctl launch") echo "com.sunnypatel.WorkoutTracker: {pid}" ;;
  "xcrun simctl spawn")
    case "$4 $5" in
      "defaults read")
        [ -f "{dir}/minimization" ] || { echo "The domain/default pair of ($6, $7) does not exist" >&2; exit 1; }
        cat "{dir}/minimization" ;;
      "defaults write") echo 0 > "{dir}/minimization" ;;
    esac ;;
  "xcrun simctl io")
    out=$8
    case "$out" in "${STUB_DENY:-/nonexistent}"/*)
      echo "Error Domain=NSCocoaErrorDomain Code=513 \\"You don't have permission to save the file.\\"" >&2; exit 1 ;;
    esac
    exec "{python}" -I -S "{dir}/recorder.py" "$out" ;;
  "xcodebuild build -project")
    project=$3 derived=$HOME/Library/Developer/Xcode/DerivedData/WorkoutTracker-test
    while [ $# -gt 0 ]; do [ "$1" != -derivedDataPath ] || derived=$2; shift; done
    if [ -n "${STUB_BUILD_HOLD:-}" ]; then
      touch "{dir}/building"
      i=0
      while [ ! -f "{dir}/release" ] && [ $i -lt 300 ]; do sleep 0.1; i=$((i + 1)); done
    fi
    [ -z "${STUB_BUILD_FAIL:-}" ] || { echo "error: stub compile error"; echo "** BUILD FAILED **"; exit 65; }
    app=$derived/Build/Products/Debug-iphonesimulator/WorkoutTracker.app
    mkdir -p "$app"
    cat "$(dirname "$project")/App/Main.swift" > "$app/WorkoutTracker.debug.dylib" ;;
  "axe describe-ui --udid") sed 's/"pid": 4121/"pid": {pid}/' "{dir}/describe-ui.json" ;;
  "axe "*) exit "${STUB_AXE_EXIT:-0}" ;;
  *) exit 1 ;;
esac
"""

RECORDER_STUB = """import os, signal, sys
stops = {signal.SIGINT, signal.SIGTERM, signal.SIGALRM}
try:
    signal.pthread_sigmask(signal.SIG_BLOCK, stops)
    if not os.environ.get("STUB_NEVER_STARTS"):
        with open("{dir}/calls", "a") as calls:
            calls.write("Recording started\\n")
        sys.stderr.write("Recording started\\n")
        sys.stderr.flush()
    signal.alarm(30)
    stop = signal.sigwait(stops)
except KeyboardInterrupt:
    stop = signal.SIGINT
if stop == signal.SIGALRM:
    sys.exit(1)
with open("{dir}/signals", "a") as signals:
    signals.write(stop.name[3:] + "\\n")
if stop == signal.SIGTERM:
    sys.exit(143)
open("{dir}/stopped", "w").close()
with open(sys.argv[1], "w") as out:
    out.write("mp4 %s\\n" % os.environ.get("STUB_MARK", ""))
"""
CLOCK_STUB = """#!/bin/sh
[ -n "${STUB_CLOCK:-}" ] || exec {real} "$@"
now=$(cat "{dir}/clock" 2>/dev/null || echo 0)
case "$(basename "$0") $*" in
  "date +%s") echo "$now" ;;
  "sleep "*[!0-9]*) exec {real} "$@" ;;
  "sleep "*) echo $((now + $1)) > "{dir}/clock" ;;
  *) exec {real} "$@" ;;
esac
"""


class Lane(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, str(self.tmp), True)
        (self.tmp / "gitconfig").touch()
        self.env = dict(os.environ, HOME=str(self.tmp / "home"), PATH="%s:%s" % (self.tmp / "bin", os.environ["PATH"]),
                        GIT_CONFIG_GLOBAL=str(self.tmp / "gitconfig"), GIT_CONFIG_NOSYSTEM="1",
                        GIT_AUTHOR_NAME="lane", GIT_AUTHOR_EMAIL="lane@example.com",
                        GIT_COMMITTER_NAME="lane", GIT_COMMITTER_EMAIL="lane@example.com", WORKOUT_ADMIT_WAIT="0")
        for name in ["SIM", "VERIFY_RUN", "VERIFY_EVIDENCE", "VERIFY_LIVE_ACTIVITIES"]:
            self.env.pop(name, None)
        self.checkout = self.tmp / "checkout"
        self.git("init", "-q", "-b", "main", str(self.checkout), cwd=self.tmp)
        for path, text in [("App/Main.swift", "v1\n"), ("Sources/WorkoutTracker/Model.swift", ""),
                           ("WorkoutShared/Shared.swift", ""), ("WorkoutWidgets/Widget.swift", ""),
                           ("WorkoutTracker.xcodeproj/project.pbxproj", ""), ("Package.swift", ""),
                           ("Package.resolved", ""), (".gitignore", "Secrets.xcconfig\n.agents/\nscripts/\n.build/\n.claude/\n")]:
            (self.checkout / path).parent.mkdir(parents=True, exist_ok=True)
            (self.checkout / path).write_text(text)
        self.git("add", "-A")
        self.git("commit", "-q", "-m", "v1")
        self.a = self.git("rev-parse", "HEAD")
        self.edit("v2\n")
        self.git("commit", "-q", "-am", "v2")
        self.b = self.git("rev-parse", "HEAD")
        self.verify_path = self.link_verify(self.checkout)
        (self.checkout / "Secrets.xcconfig").write_text("")
        derived = self.tmp / "home" / "Library" / "Developer" / "Xcode" / "DerivedData" / "WorkoutTracker-test"
        derived.mkdir(parents=True)
        (derived / "info.plist").touch()
        self.built = derived / "Build" / "Products" / "Debug-iphonesimulator" / "WorkoutTracker.app"
        self.cache = self.checkout / ".claude" / "work" / "app-cache"
        self.sim = "LANE-%d" % os.getpid()
        self.other_sim = "LANE-%d-B" % os.getpid()
        stub = LANE_STUB.replace("{dir}", str(self.tmp)).replace("{project}", str(self.checkout / "WorkoutTracker.xcodeproj"))
        gone = subprocess.Popen(["true"])
        gone.wait()
        self.app_pid = gone.pid
        stub = stub.replace("{sim}", self.sim).replace("{pid}", str(self.app_pid)).replace("{python}", sys.executable)
        axe = self.checkout / ".build" / "verify" / "node_modules" / "xcodebuildmcp" / "bundled" / "axe"
        axe.parent.mkdir(parents=True)
        (self.tmp / "bin").mkdir()
        for tool in [self.tmp / "bin" / "xcrun", self.tmp / "bin" / "xcodebuild", self.tmp / "bin" / "plutil",
                     self.tmp / "bin" / "npm", axe]:
            tool.write_text(stub)
            tool.chmod(0o755)
        (self.tmp / "bin" / "sysctl").write_text(SYSCTL_REFUSING_ALL_BUT_THE_SUITES_KNOBS)
        (self.tmp / "bin" / "sysctl").chmod(0o755)
        (self.tmp / "recorder.py").write_text(RECORDER_STUB.replace("{dir}", str(self.tmp)))
        for name in ["date", "sleep"]:
            (self.tmp / "bin" / name).write_text(CLOCK_STUB.replace("{dir}", str(self.tmp)).replace(
                "{real}", shutil.which(name, path=os.environ["PATH"])))
            (self.tmp / "bin" / name).chmod(0o755)
        (self.tmp / "describe-ui.json").write_text(MINI)
        self.simlock = FakeSimlock(self.tmp / "bin")
        self.simlock.hold(self.sim)
        self.simlock.hold(self.other_sim, requester="other-agent")
        for udid in [self.sim, self.other_sim]:
            shutil.rmtree("/tmp/workout-verify-%s" % udid, ignore_errors=True)
            self.addCleanup(shutil.rmtree, "/tmp/workout-verify-%s" % udid, True)

    def git(self, *args, cwd=None):
        done = subprocess.run(["git"] + list(args), cwd=str(cwd or self.checkout), env=self.env, check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        return done.stdout.strip()

    def link_verify(self, checkout):
        skill = link_checkout(checkout)
        (skill / "foreground.py").unlink()
        (skill / "foreground.py").write_text(FOREGROUND_STUB.replace("{dir}", str(self.tmp)))
        return skill / "verify.sh"

    def edit(self, code):
        (self.checkout / "App" / "Main.swift").write_text(code)

    def environment(self, env):
        environment = dict(self.env, SIM=self.sim)
        environment.update(env)
        return environment

    def verify(self, *argv, verify=None, **env):
        (self.tmp / "calls").unlink(missing_ok=True)
        done = subprocess.run([str(verify or self.verify_path)] + list(argv), cwd=str(self.checkout),
                              env=self.environment(env), stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              universal_newlines=True)
        return done.returncode, done.stdout, done.stderr

    def calls(self):
        calls = self.tmp / "calls"
        return calls.read_text().splitlines() if calls.exists() else []

    def own_the_app(self, owner):
        app = subprocess.Popen(FIXTURE_APP, start_new_session=True)
        self.addCleanup(app.wait)
        self.addCleanup(app.kill)
        state = Path("/tmp/workout-verify-%s" % self.sim)
        state.mkdir(parents=True, exist_ok=True)
        (state / "run").write_text("%s\n" % owner)
        (state / "pid").write_text("%d\n" % app.pid)
        return app

    def evidence(self, lane, run):
        return self.checkout / ".claude" / "work" / "evidence" / lane / run

    def launched(self, line, run="lane-1", lane="main"):
        return "launched session as pid %d on %s\n%s\nevidence %s\n" % (self.app_pid, self.sim, line, self.evidence(lane, run))

    def worktree_build(self, code, commit, dirty=""):
        return "app %s commit %s%s (this worktree's build)" % (digest(code), commit[:8], dirty)

    def cached_build(self, code, commit):
        return "app %s commit %s (cached build)" % (digest(code), commit[:8])

    def building(self, commit):
        return ("building %s into the app cache at %s (under a minute to a few; give the call a 10 min timeout)\n"
                "xcode-worktree-bootstrap: copied Secrets.xcconfig from main worktree\n" % (commit[:8], self.cache))
