#!/bin/sh
set -eu

tmp_output="$(mktemp)"
tmp_expected="$(mktemp)"
trap 'rm -f "$tmp_output" "$tmp_expected"' EXIT

cat <<'LOGO' | ./loco > "$tmp_output"
make "x 10
print :x
repeat 3 [ print sum :x 1 ]
if lessp :x 11 [ print "ok ]
ifelse greaterp :x 20 [ print "bad ] [ print "good ]
to double :n
output product :n 2
end
print double 7
LOGO

cat <<'EXPECTED' > "$tmp_expected"
10
11
11
11
ok
good
14
EXPECTED

cmp -s "$tmp_expected" "$tmp_output"

cat <<'LOGO' | ./loco > "$tmp_output"
make "q [print "stored]
run :q
run [print sum 2 3]
make "b [print "branch-ok]
if 1 :b
make "x 5
macro mydo :body
output :body
end
mydo [make "x product :x 3]
print :x
macro mywhen :cond :body
ifelse :cond [output :body] [output []]
end
mywhen 1 [print "macro-yes]
mywhen 0 [print "macro-no]
LOGO

cat <<'EXPECTED' > "$tmp_expected"
stored
5
branch-ok
15
macro-yes
EXPECTED

cmp -s "$tmp_expected" "$tmp_output"
