# Control and head on one simulator

Read `SKILL.md` first for launch, doctor, and the drive verbs. This is the recipe for running a control
commit's app and this worktree's app, the head, one after the other on one simulator.


```bash
VERIFY_RUN=ui12-control verify.sh launch --at 9a72f8dc session  # builds 9a72f8dc into the app cache once, installs, launches
verify.sh stop
verify.sh install                                              # the head: this worktree's build, replacing the control
VERIFY_RUN=ui12-head verify.sh launch session
```

`install <commit>` and `launch --at <commit>` build that commit in a scratch worktree the first
time any worktree asks, and every later call reuses the build. Give that first call a 10 minute
timeout. Two lanes that ask at once build it once, and the second says it is waiting. A build that
was killed resumes in its scratch worktree on the next call for that commit, and a call for any
other commit removes it. A bare `launch` refuses (exit 65) to replace an installed
cached build, so a head phase that skipped `install` stops instead of running the control. The cache
is `<main checkout>/.claude/work/app-cache/<sha>/`. Nothing prunes it; remove an entry by hand, and
it costs one rebuild.
