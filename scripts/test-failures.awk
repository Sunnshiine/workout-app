# Prints every failing test in a swift test or xcodebuild test log, one per line, sorted. Reads the
# whole log: Swift Testing's "Test X failed after", XCTest's "Test Case '-[M.C t]' failed", and the
# lines under xcodebuild's "Failing tests:". A name printed bare in one form and qualified by its suite
# in another prints once, qualified.

function add(name) {
  if (name ~ /^-\[[^ ]+ .+\]$/) {
    name = substr(name, 3, length(name) - 3)
    sub(/^[^ ]*\./, "", name)
    sub(/ /, ".", name)
  }
  sub(/\(\)$/, "", name)
  failed[name] = 1
}

{ gsub(/\033\[[0-9;]*m/, "") }

/^Failing tests:/ { block = 1; next }
block && /^\t/ { name = $0; sub(/^\t+/, "", name); add(name); next }
{ block = 0 }

/^[^ ]+ Test .* failed after / && !/^[^ ]+ Test run with / && !/ recorded an issue/ {
  name = $0
  sub(/^[^ ]+ Test /, "", name)
  sub(/ (with [0-9]+ test cases? )?failed after .*/, "", name)
  add(name)
  next
}

/Test Case '-\[.+\]' failed / {
  name = $0
  sub(/.*Test Case '/, "", name)
  sub(/' failed .*/, "", name)
  add(name)
}

END {
  for (name in failed)
    for (other in failed)
      if (length(other) > length(name) && substr(other, length(other) - length(name)) == "." name) qualified[name] = 1
  for (name in failed) if (!(name in qualified)) print name | "LC_ALL=C sort"
}
