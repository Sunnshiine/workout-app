#!/usr/bin/perl
# Usage: scripts/test-run-watchdog.pl LIMIT GRACE PID START MARKER
# Bounds the test run PID, which started at START (ps -o lstart= of PID, read at launch). Once PID has
# run LIMIT seconds it creates MARKER, sends SIGTERM, and sends SIGKILL GRACE seconds (at least 1) later
# if PID is still running. It checks once a second and exits as soon as PID has exited. Before every
# signal it checks that PID still carries START, and exits at once if it does not, so a pid number another
# process has since taken is never signalled. It outlives the script that started it on purpose: after
# a SIGKILL of that script, its xcodebuild still needs the bound.
use strict;
use warnings;

my ($limit, $grace, $pid, $start, $marker) = @ARGV;
die "usage: $0 LIMIT GRACE PID START MARKER\n"
  unless defined $marker && "$limit $grace $pid" =~ /^\d+ [1-9]\d* \d+$/;
$start =~ s/^\s+|\s+$//g;

# True while PID is the process that started at START and has not exited.
sub same {
  my ($now, $stat) = (`ps -o lstart= -o stat= -p $pid 2>/dev/null` =~ /^\s*(.*\S)\s+(\S+)\s*$/);
  return defined $stat && $start ne '' && $now eq $start && $stat !~ /^Z/;
}

exit 0 unless same();
for (1 .. $limit) {
  sleep 1;
  exit 0 unless same();
}
exit 0 unless same();
open my $mark, '>', $marker or die "$0: cannot create $marker: $!\n";
close $mark;
exit 0 unless same();
kill 'TERM', $pid;
for (1 .. $grace) {
  sleep 1;
  exit 0 unless same();
}
kill 'KILL', $pid;
