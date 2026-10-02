/^[^ ]+ Test .* recorded an issue/ {
  test = $0
  sub(/ recorded an issue.*/, "", test)
  if (++issues[test] <= 3) print
  else if (issues[test] == 4) print test " recorded more issues; the log holds every one"
  next
}
/^(Failing tests:|Testing failed:|xcodebuild: error:)/ { block = 1; print; next }
block && /^\t/ { print; next }
{ block = 0 }
/^[^ ]+ Test run with [1-9]/ || /Executed [1-9][0-9]* tests?, with/ { ran = 1 }
/^[^ ]+ Test run with/ || /Executed [1-9][0-9]* tests?, with/ || /^[^ ]+ Test .* failed after/ \
  || /\.swift:[0-9]+: error: / || /unexpected signal/ || /^Restarting after unexpected exit/ || /\*\* TEST EXECUTE/
END { exit !ran }
