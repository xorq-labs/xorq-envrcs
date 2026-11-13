#!/usr/bin/env bash
# Tests .envrcs/.envrc.gitignore and .envrcs/.envrc.from-template in scratch
# git repos.
#
# Each case loads a fragment through a source_env that pushd's into .envrcs/
# as direnv's does, so a path missing its $direnv_root prefix fails here as
# it would under direnv. It runs the fragment in direnv's default mode, not
# strict_env, so a failing command inside it reaches the case's checks
# rather than ending the run; one case loads under strict_env as well.
# watch_file, log_status and log_error are stubs; direnv itself is not
# needed. Needs bash, git and install.
#
# Usage: tests/test-fragments.sh   (tests the working tree it sits in)
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(cd "$(mktemp -d)" && pwd -P)
trap 'chmod -R u+rw "$work" 2>/dev/null; rm -rf "$work"' EXIT
failures=0
# No host git config: a global excludesFile would make check-ignore pass
# for a file the repo's own rules do not ignore.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

# A main checkout at $1 holding the fragments and templates under test.
# git init, not a clone: the cases need .git as a directory, a file, or
# absent, and nothing else from the repo.
scratch_repo() {
    git init -q "$1"
    git -C "$1" -c user.name=test -c user.email=test@example.invalid \
        commit -q --allow-empty -m init
    mkdir -p "$1/.envrcs"
    cp "$repo/.gitignore.template" "$1/"
    cp "$repo"/.envrcs/.envrc.{gitignore,from-template,secrets.template,user.template} "$1/.envrcs/"
}

# Load fragment $2 with direnv_root=$1, in mode $3 (default: direnv's
# default; "strict" for strict_env); stderr to $1.err. Prints, after the
# load, which of the fragments' own variables are still set. Exits non-zero
# if the load itself did, which only strict mode can do.
#
# A fresh bash process, not a subshell: `check` calls this inside an `if`,
# and bash ignores `set -e` for everything run from an `if` condition,
# subshells included, so a subshell's strict mode would test nothing.
# shellcheck disable=SC2016 # the script is for the inner bash to expand
loader='
    case $3 in
    strict) set -euo pipefail ;;
    *) set +eu +o pipefail ;;
    esac
    export direnv_root=$1
    watch_file() { :; }
    log_status() { echo "log_status: $*" >&2; }
    log_error() { echo "log_error: $*" >&2; }
    source_env() {
        pushd "$(dirname "$1")" >/dev/null
        . "./${1##*/}"
        popd >/dev/null
    }
    cd "$direnv_root"
    source_env ".envrcs/$2"
    for v in _gitignore_tmp _from_template_f _from_template_rc; do
        [ -z "${!v+set}" ] || echo "$v"
    done
'
load() {
    bash -c "$loader" load "$1" "$2" "${3:-}" 2>"$1.err"
}

check() { # <name> <command>...
    if "${@:2}"; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        failures=$((failures + 1))
    fi
}

mode_600() { [ "$(stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1")" = 600 ]; }
no_errors() { ! grep -q '^log_error' "$1"; }

# --- .envrc.gitignore ---

r=$work/g1
scratch_repo "$r"
leaked=$(load "$r" .envrc.gitignore)
check "gitignore: no .gitignore.local gives the template" cmp -s "$r/.gitignore" "$r/.gitignore.template"
check "gitignore: leaves no variable set" test -z "$leaked"
check "gitignore: the result ignores itself" git -C "$r" check-ignore -q .gitignore
check "gitignore: ... but not a nested .gitignore" eval "! git -C '$r' check-ignore -q sub/.gitignore"

r=$work/g2
scratch_repo "$r"
printf '/one' >"$r/.gitignore.template"
printf '/two\n' >"$r/.gitignore.local"
load "$r" .envrc.gitignore >/dev/null
check "gitignore: template without a final newline, then .gitignore.local" \
    test "$(cat "$r/.gitignore")" = "$(printf '/one\n/two')"

r=$work/g6
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
echo '/added-later' >>"$r/.gitignore.template"
load "$r" .envrc.gitignore >/dev/null
check "gitignore: a template edit reaches an existing .gitignore on reload" \
    cmp -s "$r/.gitignore" "$r/.gitignore.template"

r=$work/g3
scratch_repo "$r"
echo '/old' >"$r/.gitignore"
rm "$r/.gitignore.template"
load "$r" .envrc.gitignore >/dev/null
check "gitignore: no template keeps the repo's own .gitignore" test "$(cat "$r/.gitignore")" = /old
check "gitignore: no template is a silent no-op" test ! -s "$r.err"

r=$work/g4
scratch_repo "$r"
echo '/old' >"$r/.gitignore"
chmod 000 "$r/.gitignore.template"
if [ -r "$r/.gitignore.template" ]; then
    echo "skip gitignore: unreadable template (running as root: chmod 000 does not stop reads)"
else
    load "$r" .envrc.gitignore >/dev/null
    check "gitignore: unreadable template keeps the old .gitignore" test "$(cat "$r/.gitignore")" = /old
    check "gitignore: unreadable template is reported" grep -q 'not rebuilt' "$r.err"
    check "gitignore: unreadable template leaves no temp file" \
        test -z "$(find "$r" -maxdepth 1 -name '.gitignore.tmp.*')"
fi

r=$work/g5
scratch_repo "$r"
echo '/tracked' >"$r/.gitignore"
git -C "$r" add .gitignore
load "$r" .envrc.gitignore >/dev/null
check "gitignore: a tracked .gitignore is not overwritten" test "$(cat "$r/.gitignore")" = /tracked
check "gitignore: a tracked .gitignore is reported" grep -q 'is tracked' "$r.err"

# --- .envrc.from-template ---
# Each case runs .envrc.gitignore first, as the root .envrc does, so the two
# files are ignored unless the case says otherwise.

r=$work/t1
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
leaked=$(load "$r" .envrc.from-template)
for f in secrets user; do
    check "from-template: main checkout creates .envrc.$f from its template" \
        cmp -s "$r/.envrcs/.envrc.$f" "$r/.envrcs/.envrc.$f.template"
    check "from-template: .envrc.$f is mode 600" mode_600 "$r/.envrcs/.envrc.$f"
done
check "from-template: leaves no variable set" test -z "$leaked"
check "from-template: main checkout reports nothing" test ! -s "$r.err"

r=$work/t2
scratch_repo "$r"
git -C "$r" worktree add -q --detach "$work/t2-wt"
mkdir -p "$work/t2-wt/.envrcs"
cp "$r"/.gitignore.template "$work/t2-wt/"
cp "$r"/.envrcs/.envrc.* "$work/t2-wt/.envrcs/"
load "$work/t2-wt" .envrc.gitignore >/dev/null
load "$work/t2-wt" .envrc.from-template >/dev/null
check "from-template: linked worktree creates neither file" \
    test ! -e "$work/t2-wt/.envrcs/.envrc.secrets" -a ! -e "$work/t2-wt/.envrcs/.envrc.user"
check "from-template: ... and says so" grep -q 'not a main git checkout' "$work/t2-wt.err"

r=$work/t3
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
: >"$r/.envrcs/.envrc.user"
load "$r" .envrc.from-template >/dev/null
check "from-template: an existing empty .envrc.user is kept empty" test ! -s "$r/.envrcs/.envrc.user"

r=$work/t4
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
rm "$r/.envrcs/.envrc.secrets.template"
load "$r" .envrc.from-template >/dev/null
check "from-template: a missing template is skipped" test ! -e "$r/.envrcs/.envrc.secrets"
check "from-template: a missing template skips only that file" test -f "$r/.envrcs/.envrc.user"
check "from-template: a missing template reports nothing" test ! -s "$r.err"

r=$work/t5
scratch_repo "$r"
printf '%s\n' '!.envrcs/.envrc.secrets' >"$r/.gitignore.local"
load "$r" .envrc.gitignore >/dev/null
load "$r" .envrc.from-template >/dev/null
check "from-template: a file git would not ignore is not created" test ! -e "$r/.envrcs/.envrc.secrets"
check "from-template: ... and is reported as not ignored" grep -q 'envrc.secrets is not ignored' "$r.err"
check "from-template: ... and the ignored one is still created" test -f "$r/.envrcs/.envrc.user"

r=$work/t6
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
rm -rf "$r/.git"
load "$r" .envrc.from-template >/dev/null
check "from-template: no .git creates neither file" \
    test ! -e "$r/.envrcs/.envrc.secrets" -a ! -e "$r/.envrcs/.envrc.user"

# git that cannot answer: a corrupt index makes check-ignore exit 128.
r=$work/t7
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
echo garbage >"$r/.git/index"
load "$r" .envrc.from-template >/dev/null
check "from-template: git failing creates neither file" \
    test ! -e "$r/.envrcs/.envrc.secrets" -a ! -e "$r/.envrcs/.envrc.user"
check "from-template: ... and says git could not tell, not 'not ignored'" \
    grep -q 'git could not say' "$r.err"

# --- both, under strict_env ---

r=$work/s1
scratch_repo "$r"
check "strict_env: .envrc.gitignore loads" load "$r" .envrc.gitignore strict
check "strict_env: .envrc.from-template loads" load "$r" .envrc.from-template strict
check "strict_env: ... and creates both files" \
    test -f "$r/.envrcs/.envrc.secrets" -a -f "$r/.envrcs/.envrc.user"
r=$work/s2
scratch_repo "$r"
load "$r" .envrc.gitignore >/dev/null
printf '%s\n' '!.envrcs/.envrc.secrets' >>"$r/.gitignore"
check "strict_env: a refused file does not abort the load" load "$r" .envrc.from-template strict

if [ "$failures" -ne 0 ]; then
    echo "$failures failed"
    exit 1
fi
echo "all passed"
