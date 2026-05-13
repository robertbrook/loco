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
pr sum 2 3
print remainder 7 3
print minus 5
print less? 2 3
print and 1 0
print not 0
print word "lo "go
print list "a "b
print first [ 10 20 30 ]
print last [ 10 20 30 ]
print bf [ 10 20 30 ]
print bl [ 10 20 30 ]
print count [ 10 20 30 ]
print item 2 [ 10 20 30 ]
print emptyp [ ]
print word? "abc
print list? [ x ]
print number? "42
print member? "20 [ 10 20 30 ]
run [ print "ran ]
to add2 :n
op sum :n 2
end
print add2 5
LOGO

cat <<'EXPECTED' > "$tmp_expected"
5
1
-5
1
0
1
logo
[a b]
10
30
[20 30]
[10 20]
3
20
1
1
1
1
1
ran
7
EXPECTED

cmp -s "$tmp_expected" "$tmp_output"
