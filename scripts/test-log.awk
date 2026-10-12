# Reads a swift build, swift test, or xcodebuild log and prints the answer -v mode asks for:
#   failures     every failing test, one per line, sorted: Swift Testing's "Test X failed after",
#                XCTest's "Test Case '-[M.C t]' failed", and the lines under xcodebuild's "Failing
#                tests:". A name printed bare in one form and qualified in another prints once,
#                qualified. A test process that died on a signal, or left a test started and never
#                finished, adds "X (crashed)" when X was its one running test and "(test process
#                crashed)" otherwise.
#   count        the tests that ran: Swift Testing's run line plus XCTest's Executed line
#   first-error  the compiler's first file:line: error (a parse error rewritten to that form), else
#                the first recorded issue, else the first error: line, else the last line.
#                -v root=DIR/ strips DIR/ from it.

BEGIN {
  if (mode != "failures" && mode != "count" && mode != "first-error") {
    print "usage: awk -v mode=failures|count|first-error [-v root=DIR/] -f test-log.awk LOG" > "/dev/stderr"
    usage = 1
    exit 2
  }
}

function norm(name) {
  if (name ~ /^-\[[^ ]+ .+\]$/) {
    name = substr(name, 3, length(name) - 3)
    sub(/^[^ ]*\./, "", name)
    sub(/ /, ".", name)
  }
  sub(/\(\)$/, "", name)
  return name
}

function unrooted(s,    p) {
  if (root == "") return s
  while ((p = index(s, root)) > 0) s = substr(s, 1, p - 1) substr(s, p + length(root))
  return s
}

{ gsub(/\033\[[0-9;]*m/, "") }

mode == "first-error" {
  if (/^[^ ]+:[0-9]+(:[0-9]+)?: error: / || / Test .* recorded an issue/) { found = $0; exit }
  # SwiftPM prints a parse error, #error included, as "error: FILE:LINE:COL message".
  if (/^error: [^ ]+:[0-9]+:[0-9]+ /) { found = $2 ": error:" substr($0, length($1 " " $2) + 1); exit }
  if (first == "" && /error:/) first = $0
  last = $0
  next
}

/ Test run with [0-9]+ tests? / { for (i = 1; i < NF; i++) if ($i == "with") { run = $(i + 1); break } }
/Executed [0-9]+ tests?, with/ { for (i = 1; i < NF; i++) if ($i == "Executed") executed = $(i + 1) }
mode == "count" { next }

/exited with unexpected signal/ { signaled = 1 }

/^Failing tests:/ { block = 1; next }
block && /^\t/ { name = $0; sub(/^\t+/, "", name); failed[norm(name)] = 1; next }
{ block = 0 }

/^[^ ]+ Test .* started\.$/ && !/^[^ ]+ Test (run|case passing .*) started/ {
  name = $0
  sub(/^[^ ]+ Test /, "", name)
  sub(/ started\.$/, "", name)
  running[norm(name)] = 1
  swiftTesting[norm(name)] = 1
  next
}

# Swift Testing ends a passing run with this line, so a test it left started passed; its line was lost.
/^[^ ]+ Test run with [0-9]+ tests? .* passed after / { for (name in swiftTesting) delete running[name] }

/^[^ ]+ Test .* (passed|failed) after / && !/^[^ ]+ Test run with / && !/ recorded (an|a known) issue/ {
  name = $0
  sub(/^[^ ]+ Test /, "", name)
  sub(/ (with [0-9]+ test cases? )?(passed|failed) after .*/, "", name)
  delete running[norm(name)]
  if ($0 ~ / failed after /) failed[norm(name)] = 1
  next
}

/Test Case '-\[.+\]' (started|passed|failed|skipped)/ {
  name = $0
  sub(/.*Test Case '/, "", name)
  sub(/' (started|passed|failed|skipped).*/, "", name)
  if ($0 ~ /' started/) running[norm(name)] = 1
  else delete running[norm(name)]
  if ($0 ~ /' failed /) failed[norm(name)] = 1
}

END {
  if (usage) exit 2
  if (mode == "first-error") {
    if (found == "") found = first != "" ? first : last
    print unrooted(found)
    exit
  }
  if (mode == "count") { print run + executed; exit }
  unfinished = 0
  for (name in running) { unfinished++; crashed = name }
  if (unfinished == 1) failed[crashed " (crashed)"] = 1
  else if (signaled || unfinished > 1) failed["(test process crashed)"] = 1
  for (name in failed)
    for (other in failed)
      if (length(other) > length(name) && substr(other, length(other) - length(name)) == "." name) qualified[name] = 1
  for (name in failed) if (!(name in qualified)) print name | "LC_ALL=C sort"
}
