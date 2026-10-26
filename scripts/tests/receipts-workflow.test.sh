#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

echo "receipts.yml: a title-only edit skips under a concurrency group of its own, so it cancels no run"
cat >"$root/workflow.py" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
group = re.search(r"^concurrency:\n  group: (.+)$", src, re.M).group(1)
cond = re.search(r"^  receipts:\n(?:    .*\n)*?    if: (.+)$", src, re.M).group(1)
TOKEN = re.compile(r"\s+|'[^']*'|&&|\|\||!=|==|!(?=[A-Za-z(])|\(|\)|[A-Za-z_][\w.-]*")

def evaluate(expr, ctx):
    out, pos = [], 0
    while pos < len(expr):
        m = TOKEN.match(expr, pos)
        if not m:
            raise SystemExit(f"bad\tan expression token the test cannot read: {expr[pos:]}")
        t, pos = m.group(0), m.end()
        if t.isspace():
            continue
        out.append({"&&": " and ", "||": " or ", "!": " not "}.get(t, t if t[0] in "'()!=" else f"get({t!r})"))
    def get(path):
        v = ctx
        for k in path.split("."):
            v = v.get(k) if isinstance(v, dict) else None
        return v
    return eval("".join(out), {"get": get})

def template(text, ctx):
    return re.sub(r"\$\{\{(.*?)\}\}", lambda m: str(evaluate(m.group(1), ctx)), text)

def event(run_id, action, **changes):
    return {"github": {"run_id": run_id, "event": {"action": action, "changes": changes, "pull_request": {"number": 1110}}}}

events = {
    "a push": event(1, "synchronize"),
    "a body edit": event(2, "edited", body={"from": "old"}),
    "a base edit": event(3, "edited", base={"ref": {"from": "old"}}),
    "a title edit": event(4, "edited", title={"from": "old"}),
}
types = re.search(r"^    types: \[(.*)\]$", src, re.M).group(1).split(", ")
print(f"{'ok' if 'edited' in types else 'bad'}\treceipts.yml: a body edit starts a run (types {types})")
cancel = re.search(r"^  cancel-in-progress: (.+)$", src, re.M).group(1)
print(f"{'ok' if cancel == 'true' else 'bad'}\treceipts.yml: a newer run cancels the PR group's older one (cancel-in-progress {cancel})")
push_group = template(group, events["a push"])
for label, ctx in events.items():
    runs, own = bool(evaluate(cond, ctx)), template(group, ctx)
    title = label == "a title edit"
    print(f"{'ok' if runs != title else 'bad'}\treceipts.yml: {label} {'skips' if title else 'runs'} the job")
    shares = own == push_group
    print(f"{'ok' if shares != title else 'bad'}\treceipts.yml: {label} {'has a group of its own' if title else 'shares the PR group'} (group {own})")
PY
while IFS=$'\t' read -r verdict text; do
    if [ "$verdict" = ok ]; then ok "$text"; else bad "$text"; fi
done < <(python3 -I "$root/workflow.py" "$script_dir/../../.github/workflows/receipts.yml" 2>&1 || echo "bad	the workflow check crashed")

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
