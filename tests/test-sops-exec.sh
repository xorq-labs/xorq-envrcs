#!/usr/bin/env bash
# Tests .envrcs/sops-exec, the per-call wrapper sops_wrap links, called
# directly: each case lays out a wrapper directory by hand (the link and its
# .sops-wrap) rather than through sops_wrap, so direnv is not needed. `sops`
# is a stub that prints $STUB_VALUE as the decrypted value and exits
# $STUB_RC (default 0), so no key and no real bundle are involved; values
# here are dummies. Needs bash, sed,
# timeout, and a `true` on disk (`type -P true`), not only the builtin.
# Not a full harness for sops_wrap: that is kata xorq-envrcs#2eg8.
#
# Usage: tests/test-sops-exec.sh   (tests the working tree it sits in)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$work"' EXIT
failures=0

bin=$work/bin
mkdir -p "$bin"
# No newline after the value: `sops --extract --output-type binary` adds
# none (sops 3.13.3, od -c). A value holding `\n` is stored as those two
# characters and printed with a real newline, as sops decodes it.
# shellcheck disable=SC2016 # for the stub to expand
printf '#!/usr/bin/env bash\nprintf "%%s" "$STUB_VALUE"\nexit "${STUB_RC:-0}"\n' >"$bin/sops"
# shellcheck disable=SC2016 # for the stub to expand
printf '#!/usr/bin/env bash\nprintf "X=[%%s]\\n" "${X-unset}"\n' >"$bin/show"
chmod +x "$bin/sops" "$bin/show"
# A compiled tool, as the real kata is: the host's `true` binary, copied
# under its own name (a multicall coreutils runs only as a name it knows).
cp "$(type -P true)" "$bin/true"

# A wrapper for tool $1 that maps X to bundle key K, as sops_wrap writes it.
wrap() {
    local d=$work/w/$1
    mkdir -p "$d"
    ln -s "$repo/.envrcs/sops-exec" "$d/$1"
    printf 'envrcs=%q\nbundle=%q\nmap=%q\nfixed=()\n' \
        "$repo/.envrcs" /dev/null 'X=K' >"$d/.sops-wrap"
}
wrap true
wrap show

# Run wrapped tool $1 with stub value $2, no tty on any fd; stdout to
# $work/out, stderr to $work/err. By path, as PATH would find it: a bare
# `true` would run bash's builtin.
call() {
    PATH=$work/w/$1:$bin:$PATH STUB_VALUE=$2 "$work/w/$1/$1" </dev/null >"$work/out" 2>"$work/err"
}

check() { # <name> <command>...
    if "${@:2}"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        failures=$((failures + 1))
    fi
}
silent() { [ ! -s "$work/err" ]; }
got() { [ "$(cat "$work/out")" = "$1" ]; }
refused() { # <rc> <stderr text>: refused with that text, the value unnamed
    [ "$1" -eq 1 ] && [ ! -s "$work/out" ] && grep -qF "$2" "$work/err" &&
        ! grep -qF "$3" "$work/err"
}

# --- the PATH walk ---

rc=0; call true v || rc=$?
check "a compiled real tool runs, exit 0" [ "$rc" -eq 0 ]
check "... with nothing on stderr" silent

# Another checkout's wrapper, a copy of sops-exec rather than a link to this
# one, earlier on PATH: skipped by its marker line, or the two exec each
# other until the timeout.
other=$work/other
mkdir -p "$other/w/show"
cp "$repo/.envrcs/sops-exec" "$other/sops-exec"
ln -s "$other/sops-exec" "$other/w/show/show"
cp "$work/w/show/.sops-wrap" "$other/w/show/"
rc=0
PATH=$work/w/show:$other/w/show:$bin:$PATH STUB_VALUE=zq9 \
    timeout 10 "$work/w/show/show" </dev/null >"$work/out" 2>"$work/err" || rc=$?
check "another checkout's wrapper on PATH is skipped" got 'X=[zq9]'

# The marker counts on line 2 only: a real tool that carries the same text
# on a later line (here a script quoting it) is still the one run.
late=$work/late
mkdir -p "$late"
printf '#!/usr/bin/env bash\n# a tool, not a wrapper\n# sops_wrap wrapper (quoted)\necho late-ran\n' >"$late/show"
chmod +x "$late/show"
rc=0
PATH=$work/w/show:$late:$bin:$PATH STUB_VALUE=zq9 \
    "$work/w/show/show" </dev/null >"$work/out" 2>"$work/err" || rc=$?
check "a tool with the marker text on a later line is run" got 'late-ran'

# --- the decrypt ---

# sops fails after printing something: refused, and what it printed never
# reaches the tool (a `;` for the `&&` before the sentinel, or a missing
# exit, would deliver it).
rc=0; STUB_RC=1 call show zq9 || rc=$?
check "a failing decrypt is refused, naming the key" \
    refused "$rc" 'could not decrypt K from /dev/null' 'zq9'
# Only the one trailing sentinel x comes off, not everything from an x on.
call show abx123 || true
check "a value holding x reaches the tool whole" got 'X=[abx123]'
rc=0; call show '' || rc=$?
check "an empty value is refused, naming the key" \
    refused "$rc" 'K in /dev/null is empty' 'X=['

# --- quotes (README, "Quotes"): each case below is delivered as use_sops delivers it, or refused ---

call show zq9 || true
check "a plain value reaches the tool" got 'X=[zq9]'
call show "'a b#c'" || true
check "a single-quoted value with space and # reaches the tool, unquoted" got 'X=[a b#c]'
# sops decodes a stored \n to a newline; use_sops delivers the two
# characters, so the wrapper turns it back. Trailing ones too.
call show $'a\nb' || true
check "an unquoted \\n reaches the tool as \\n, not a newline" got 'X=[a\nb]'
call show $'\'a\nb\'' || true
check "a single-quoted \\n reaches the tool as \\n" got 'X=[a\nb]'
call show $'zq9\n\n' || true
check "trailing \\n's reach the tool" got 'X=[zq9\n\n]'
# Double-quoted, direnv dotenv reads \n as a newline as sops does, so the
# newline stays.
call show $'"l1\nl2"' || true
check "a double-quoted \\n reaches the tool as a newline" got $'X=[l1\nl2]'
rc=0; call show '"a$b"' || rc=$?
check "a double-quoted \$ is refused, naming the key" \
    refused "$rc" 'K in /dev/null is double-quoted with \ or $ in it' 'a$b'
for v in 'zq9 # note' 'zq9#note' 'zq9 x' ' zq9' 'zq9 ' $'zq9\tx'; do
    rc=0; call show "$v" || rc=$?
    check "unquoted '$v' is refused, naming the key" \
        refused "$rc" 'K in /dev/null is unquoted with whitespace or # in it' "$v"
done

if [ "$failures" -ne 0 ]; then
    echo "$failures failed"
    exit 1
fi
echo "all passed"
