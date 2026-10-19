"""The path work behind scripts/seed-packages.sh (docs/agents/dependency-store.md).

  derived-dir <project>       print the DerivedData dir Xcode names for <project>
  workspace <dir>             print the WorkspacePath <dir>/info.plist names; exit 1 without one
  install <staging> <final>   point a cloned SourcePackages at <final>, then rename it there;
                              exit 1 when its paths name two roots, 3 when <final> exists
"""

import glob
import hashlib
import json
import os
import plistlib
import re
import sys

ROOT = re.compile(r"(/[^\s\"]*?/SourcePackages)(?=/)")


def derived_dir(project):
    # Xcode hashes the path after stringByStandardizingPath, which drops a leading /private when
    # the rest still exists. Each 8-byte half of the MD5 becomes 14 base-26 letters.
    if project.startswith("/private/") and os.path.exists(project[len("/private") :]):
        project = project[len("/private") :]
    digest = hashlib.md5(project.encode()).digest()
    name = ""
    for half in (digest[:8], digest[8:]):
        n = int.from_bytes(half, "big")
        letters = []
        for _ in range(14):
            n, r = divmod(n, 26)
            letters.append(chr(ord("a") + r))
        name += "".join(reversed(letters))
    stem = os.path.splitext(os.path.basename(project))[0]
    return os.path.join(os.path.expanduser("~/Library/Developer/Xcode/DerivedData"), f"{stem}-{name}")


def workspace(directory):
    try:
        with open(os.path.join(directory, "info.plist"), "rb") as f:
            path = plistlib.load(f).get("WorkspacePath")
    except (OSError, plistlib.InvalidFileException):
        return 1
    if not isinstance(path, str):
        return 1
    print(path)
    return 0


def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for v in value.values():
            yield from strings(v)
    elif isinstance(value, list):
        for v in value:
            yield from strings(v)


def moved(value, old, new):
    if isinstance(value, str):
        return new + value[len(old) :] if value.startswith(old + "/") else value
    if isinstance(value, dict):
        return {k: moved(v, old, new) for k, v in value.items()}
    if isinstance(value, list):
        return [moved(v, old, new) for v in value]
    return value


# Xcode leaves each checkout's git files read-only, so a new file with the same mode replaces each.
def replace(path, text):
    mode = os.stat(path).st_mode & 0o7777
    with open(path + ".seeding", "w") as f:
        f.write(text)
    os.chmod(path + ".seeding", mode)
    os.replace(path + ".seeding", path)


# The producer's SourcePackages path is in workspace-state.json (the SwiftLint artifact bundle) and
# in each checkout's git origin URL and object alternates, which point at repositories/.
def install(staging, final):
    state_path = os.path.join(staging, "workspace-state.json")
    with open(state_path) as f:
        state = json.load(f)
    git_paths = glob.glob(os.path.join(staging, "checkouts/*/.git/config"))
    git_paths += glob.glob(os.path.join(staging, "checkouts/*/.git/objects/info/alternates"))
    git_files = {}
    for path in git_paths:
        with open(path) as f:
            git_files[path] = f.read()
    roots = {m for s in strings(state) for m in ROOT.findall(s)}
    roots |= {m for text in git_files.values() for m in ROOT.findall(text)}
    if len(roots) > 1:
        print(f"seed-packages: the stored packages name {len(roots)} roots: {sorted(roots)}", file=sys.stderr)
        return 1
    old = roots.pop() if roots else final
    if old != final:
        replace(state_path, json.dumps(moved(state, old, final), indent=2))
        for path, text in git_files.items():
            replace(path, text.replace(old + "/", final + "/"))
    try:
        os.rename(staging, final)
    except OSError:
        if os.path.exists(final):
            return 3
        raise
    return 0


def main(argv):
    if len(argv) == 2 and argv[0] == "derived-dir":
        print(derived_dir(argv[1]))
        return 0
    if len(argv) == 2 and argv[0] == "workspace":
        return workspace(argv[1])
    if len(argv) == 3 and argv[0] == "install":
        return install(argv[1], argv[2])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
