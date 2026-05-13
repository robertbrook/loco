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
