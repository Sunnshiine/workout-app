import json, sys
try:
    s = json.load(open(sys.argv[1]))
except Exception as e:
    print(f"summary=unreadable({e.__class__.__name__})"); sys.exit()
fails = sorted({f.get("testIdentifierString") or f.get("testName", "?") for f in s.get("testFailures", [])})
slow = []
try:
    def walk(n):
        if n.get("nodeType") == "Test Case":
            d = n.get("durationInSeconds") or 0
            slow.append((d, n.get("nodeIdentifier") or n.get("name")))
        for c in n.get("children", []):
            walk(c)
    for n in json.load(open(sys.argv[2])).get("testNodes", []):
        walk(n)
except Exception:
    pass
print(f"passed={s.get('passedTests')} failed={s.get('failedTests')} skipped={s.get('skippedTests')} total={s.get('totalTestCount')} "
      f"start={s.get('startTime')} finish={s.get('finishTime')} sumtests={sum(d for d, _ in slow):.0f} failing={','.join(fails) or '-'}")
