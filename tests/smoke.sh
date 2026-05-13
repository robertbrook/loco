#!/bin/sh
set -eu

tmp_output="$(mktemp)"
tmp_expected="$(mktemp)"
tmp_more_output="$(mktemp)"
tmp_more_expected="$(mktemp)"
tmp_words_output="$(mktemp)"
trap 'rm -f "$tmp_output" "$tmp_expected" "$tmp_more_output" "$tmp_more_expected" "$tmp_words_output"' EXIT

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

# Test: additional non-graphics words
cat <<'LOGO' | ./loco > "$tmp_more_output"
print word "lo "go
print sentence "hello "world
print list "a "b
print first "logo
print last "logo
print butfirst "logo
print butlast "logo
print item 2 "logo
print count "logo
print and 1 0
print or 0 2
print not 0
print numberp "123
print wordp 10
print emptyp "
print notequalp 1 2
print equal? 3 3
print less? 1 2
print greater? 3 2
print member "go "logo
print memberp "go "logo
to scoped
local "x
make "x 5
localmake "x 9
output :x
end
print scoped
LOGO

cat <<'EXPECTED' > "$tmp_more_expected"
logo
hello world
a b
l
o
ogo
log
o
4
0
1
1
1
1
1
1
1
1
1
go
1
9
EXPECTED

cmp -s "$tmp_more_expected" "$tmp_more_output"

# Test: words prints built-in and user-defined procedures
cat <<'LOGO' | ./loco > "$tmp_words_output"
to greet
print "hello
end
words
LOGO

# Verify that known built-in words appear in output
for word in print type show make local localmake repeat if ifelse output stop words sum difference product quotient remainder modulo power sqrt int round abs minus random lessp greaterp equalp less? greater? equal? notequalp notequal? and or not numberp wordp listp emptyp memberp word sentence se list first last butfirst bf butlast bl item count member thing greet; do
    grep -qw "$word" "$tmp_words_output" || { echo "FAIL: '$word' not found in words output"; exit 1; }
done
