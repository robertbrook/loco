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

# Test: words prints built-in and user-defined procedures
tmp_words_output="$(mktemp)"
trap 'rm -f "$tmp_output" "$tmp_expected" "$tmp_words_output"' EXIT

cat <<'LOGO' | ./loco > "$tmp_words_output"
to greet
print "hello
end
words
LOGO

# Verify that known built-in words appear in output
for word in print make repeat if ifelse output stop words sum difference product quotient lessp greaterp equalp thing greet; do
    grep -qw "$word" "$tmp_words_output" || { echo "FAIL: '$word' not found in words output"; exit 1; }
done

# Test: additional non-graphics words
tmp_extra_output="$(mktemp)"
tmp_extra_expected="$(mktemp)"
trap 'rm -f "$tmp_output" "$tmp_expected" "$tmp_words_output" "$tmp_extra_output" "$tmp_extra_expected"' EXIT

cat <<'LOGO' | ./loco > "$tmp_extra_output"
print abs -5
print remainder 10 3
print word "lo "go
print list "a "b
print sentence [ a b ] [ c ]
print first [ x y z ]
print butfirst [ x y z ]
print item 2 [ x y z ]
print count [ x y z ]
print and 1 0
print or 1 0
print not 0
run [ print "ran ]
LOGO

cat <<'EXPECTED' > "$tmp_extra_expected"
5
1
logo
[a b]
[a b c]
x
[y z]
y
3
0
1
1
ran
EXPECTED

cmp -s "$tmp_extra_expected" "$tmp_extra_output"
