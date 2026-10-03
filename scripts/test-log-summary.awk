/^[^ ]+ Test .* recorded an issue/ {
  test = $0
  sub(/ recorded an issue.*/, "", test)
  shown = ++issues[test] <= 3
  operand = 0
  if (shown) print
  else if (issues[test] == 4) print test " recorded more issues; the log holds every one"
  next
}
shown && /^(↳| )/ {
  if (/^↳   [^ ]/) { print; operand = !/ → / }
  else if (operand && / → /) { print; operand = 0 }
  next
}
{ shown = 0 }
/^(Failing tests:|Testing failed:|xcodebuild: error:)/ { block = 1; print; next }
block && /^\t/ { print; next }
{ block = 0 }
/^[^ ]+ Test run with [1-9]/ { ran = 1 }
/Executed [1-9][0-9]* tests?, with/ { ran = 1; if (outermost) print }
{ outermost = /^Test Suite '(All|Selected) tests' / }
/^[^ ]+ Test run with/ || /^[^ ]+ Test .* failed after/ \
  || /\.swift:[0-9]+: error: / || /unexpected signal/ || /^Restarting after unexpected exit/ || /\*\* TEST EXECUTE/
END { exit !ran }
