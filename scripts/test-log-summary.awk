/^[^ ]+ Test .* recorded an issue/ {
  test = $0
  sub(/ recorded an issue.*/, "", test)
  expression = $0
  if (!sub(/.*Expectation failed: /, "", expression)) expression = ""
  operand = 0
  mode = ++issues[test] <= 3 ? "issue" : ""
  if (mode) print
  else if (issues[test] == 4) print test " recorded more issues; the log holds every one"
  next
}
mode == "issue" && /^(↳| )/ {
  if (/^↳ [^ ]/) { if ($0 != "↳ " expression && index($0, "↳ " expression " → ") != 1) print }
  else if (/^↳   [^ ]/) { print; operand = !/ → / }
  else if (operand && / → /) { print; operand = 0 }
  next
}
/^(Failing tests:|Testing failed:|xcodebuild: error:)/ { mode = "block"; print; next }
mode == "block" && /^\t/ { print; next }
{ mode = "" }
/^[^ ]+ Test run with [1-9]/ { ran = 1 }
/Executed [1-9][0-9]* tests?, with/ { ran = 1; if (previous ~ /^Test Suite '(All|Selected) tests' /) print }
/^[^ ]+ Test run with/ || /^[^ ]+ Test .* failed after/ \
  || /\.swift:[0-9]+: error: / || /unexpected signal/ || /^Restarting after unexpected exit/ || /\*\* TEST EXECUTE/
{ previous = $0 }
END { exit !ran }
