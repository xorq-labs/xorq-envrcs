# .envrcs/

direnv configuration split into composable fragments, sourced from the root `.envrc`.

## Tracked (templates & helpers)

| File | Purpose |
|---|---|
| `.envrc.sops` | Defines `use_sops` and `use_sops_if_exists` for decrypting secrets into the environment, and `sops_wrap` for handing them to one command per call |
| `sops-exec` | The wrapper `sops_wrap` links each wrapped tool to; also holds the no-tty gpg rule every sops call here uses |
| `sops-gpg-no-pinentry` | The gpg a sops call runs with no tty: yours, with `--pinentry-mode error` |
| `.envrc.nix-config` | Bootstraps nix-direnv; where to `watch_file` imported nix modules |
| `.envrc.secrets.template` | Decrypts `.env.secrets.demo.sops-encrypted`; shows how to add further bundles |
| `.envrc.user.template` | Default user env: loads `.env.local`; both toolchain fragments commented, pick one; kenn layer commented, optional |
| `.envrc.user.flake` | User env variant: nix flake (immutable install); no-ops without a `flake.nix`, and watches for one appearing |
| `.envrc.user.uv` | User env variant: uv sync + venv activation; guards on `pyproject.toml` existing, not on whether you use uv |
| `.envrc.user.kenn` | Additive user layer: kenn-io toolkit (kata, kwt, roborev, ...) on PATH from the devcontainer flake |
| `kenn.rev` | The one devcontainer revision `.envrc.user.kenn` builds from |
| `.envrc.kata` | Opt-in: kata calls go to a team server, from `KATA_TEAM_SERVER` and a `KATA_TEAM_TOKEN` key kata gets per call |
| `.env.local.template` | Third layer: per-user, non-secret dotenv values |
| `.env.secrets.demo.sops-encrypted` | Encrypted demo bundle the secrets layer decrypts |
| `demo-age-key.txt` | Throwaway private key for the demo bundle — committed on purpose, see below |

The root also tracks `.gitignore.template`, which generates the repo's
`.gitignore` (see below).

## Untracked (local / secret)

Never commit these. The generated `.gitignore` covers them — but only the
generated one: the root `.envrc` skips the auto-create when the repo already
has a `.gitignore`, which is the normal case for a repo adopting this layout.
**If you brought your own `.gitignore`, add these rules to it yourself:**

```gitignore
# plaintext secret sources — the ones that actually matter
.env
*.env
.envrcs/.env.*

# auto-created local fragments
.envrcs/.envrc.secrets
.envrcs/.envrc.user

# build products of the user layer
.direnv
.venv
/result
/result-*

# tracked exceptions, and they must come last
!.envrcs/.env.*.template
!*.sops-encrypted
```

This is the whole of `.gitignore.template` minus its self-ignore line; if the
two ever drift, that file is the source of truth.

Until you do, `direnv allow` creates `.envrcs/.envrc.secrets` as an ordinary
untracked file that `git add -A` will happily stage. By default it holds no
secret material — `source_env .envrc.sops`, and a `use sops_if_exists` call
prefixed with `SOPS_AGE_KEY_FILE=...` for the demo bundle — but it is a
shell fragment, so a stray `export SECRET=...` typed into it would be staged
too, and mode `600` protects it from other local users, not from git.

| File | Created from | Auto-created? |
|---|---|---|
| `.envrc.secrets` | `.envrc.secrets.template` | yes, mode `600` |
| `.envrc.user` | `.envrc.user.template` | yes, mode `600` |
| `.env.local` | `.env.local.template` | **no** — copy manually |
| `.env`, `*.env` | plaintext secret sources — never committed | no |

`.env.secrets.demo.sops-encrypted` is a dotenv-format, sops-encrypted demo
bundle. It is committed because it is encrypted — the plaintext it was built
from is not, and is covered by the ignore rules. It is a single-bundle
*demo*; the intended production shape is one concatenated bundle, described
below.

### The committed demo key

`demo-age-key.txt` is an age **private** key, committed deliberately. A demo
bundle is only a demo if every clone can decrypt it; encrypting it to one
person's key would mean a wall of sops errors on `direnv allow` for everyone
else, and "a fresh clone needs only `direnv allow`" would be false. The key
guards nothing: the whole plaintext is `secret=value`.

`.envrc.secrets.template` names it as a var-assignment prefix on the one call
that needs it, so `SOPS_AGE_KEY_FILE` is discarded when the function returns
and cannot become the default for a real bundle. A real bundle is encrypted
to the recipients who should read it, and their private keys never enter the
repo.

## Auto-create, and how to disable a fragment

The root `.envrc` creates `.gitignore`, `.envrc.secrets` and `.envrc.user`
from their templates if they are missing, so `direnv allow` is the only step
on a fresh clone. Existing files are never overwritten — a repo adopting this
layout keeps its own `.gitignore`, and a symlink to a template counts as
existing.

Because of the auto-create, **deleting one of these files does not disable
it** — it is recreated from the template on the next `direnv allow`/reload.
To durably disable a fragment, empty it instead:

```sh
> .envrcs/.envrc.user     # skip the user layer entirely
```

Note what "entirely" covers: `.env.local` is loaded *by* `.envrc.user`, not
by the root `.envrc`, so emptying the user layer silently takes the third
layer with it. The three layers are peers in what they hold, not in how they
are wired — see the tree at the end of this file. To keep `.env.local` while
dropping the toolchain, comment out the `source_env` line instead of emptying
the file.

An existing-but-empty file satisfies the auto-create check and is a no-op
when sourced.

**To drop a layer for the whole repo, stop tracking its template.** The
auto-create skips a file whose template is absent, and the root `.envrc`
sources each fragment with `source_env_if_exists`, so a missing layer is a
silent no-op rather than an error on every reload (or an aborted load under
`strict_env`). The root `.envrc` needs no edit, which keeps it identical
across every repo using this layout. Two consequences:

- Checkouts that already generated the fragment keep sourcing it; removing
  the template only stops new copies. Delete the local file too.
- Removing `.envrc.user.template` drops `.env.local` with it, for the reason
  above.

The skip applies only to a missing template. If the template is there and
`install` fails for another reason, that still surfaces.

**If you symlinked the local file to its template** instead of copying it,
do not empty it — you would truncate the tracked template. Replace the
symlink with a real copy first (`cp --remove-destination
.envrcs/.envrc.user.template .envrcs/.envrc.user`), or comment out the lines
you want off. Editing through a symlink shows up as a dirty tracked file in
`git status`, which is the tell.

## The three layers

1. **`.envrc.secrets`** — sops-encrypted material. Shell fragment; sources
   `.envrc.sops`, calls `use_sops_if_exists` per bundle that must be ambient,
   and names the bundles per-call wrappers read.
2. **`.envrc.user`** — per-user shell logic: which toolchain to bring up
   (`uv` or `flake`), anything needing conditionals or command substitution.
   The template ships with both toolchain lines commented out — which one a
   checkout wants is a per-user choice, and neither fragment is a sensible
   default to impose. Uncomment one.
3. **`.env.local`** — per-user, non-secret values. Loaded with
   `dotenv_if_exists`, so it is parsed as `KEY=value` by `direnv dotenv`, not
   sourced as shell.

`.env.local` is deliberately *not* auto-created: its template presents
mutually exclusive strategies, and silently applying both would leave the
environment in a state nobody asked for. Copy it and uncomment at most one.

The rules that cover all of this, and the reason for each, are in
`.gitignore.template` itself; the block under
[Untracked](#untracked-local--secret) above is a copy of it for adopters.
Both are wholesale rather than per-file, so a future per-user dotenv
fragment is covered without an edit.

## sops

`use_sops` watches the encrypted file *before* decrypting, so a file that
fails to decrypt is still watched and fixing it (or the key) retriggers the
reload. A failed `sops --decrypt` is reported via `log_error` and returns
non-zero for callers that check it. direnv evaluates `.envrc` without
`errexit`, so the load continues either way — what the check buys is the
error message, instead of the silent empty environment a pipeline gives you
by discarding the decrypt's exit status.

The `direnv dotenv` parse is captured and checked for the same reason. The
two parsers do not agree: sops will happily encrypt `NOTE=he said "hi"`, and
`direnv dotenv` rejects the decrypted result as an invalid line. Piped
straight into `eval`, that is an empty environment reported as success.

Only `dotenv` bundles are supported. The `output_type` parameter exists to
reject anything else: any other type would have to be `eval`d as shell, and a
YAML or JSON payload run that way is a syntax error at best and arbitrary
command execution at worst.

Both helpers need `$direnv_root` to build their default path. If it is unset
— this fragment reused somewhere that does not export it — they `log_error`
and return non-zero instead of defaulting to `/.envrcs/...` and quietly
doing nothing.

`use_sops_if_exists` watches the path *before* testing whether it exists,
mirroring direnv's own `source_env_if_exists` and `dotenv_if_exists`. A
missing file is recorded as a watch with `exists:false`, so building the
bundle later retriggers the reload rather than leaving the secrets layer
silently empty until someone runs `direnv reload` by hand. The same applies
to the `flake.nix`/`pyproject.toml` guards in the user fragments.

`use_sops_if_exists` shares `use_sops`' default path,
`$direnv_root/.envrcs/.env.secrets.concatenated.sops-encrypted` — the
production bundle below — so a bare `use sops_if_exists` decrypts it instead
of silently doing nothing. This repo ships no such bundle, so the bare form
no-ops here and the demo names its file explicitly.

### Quote values containing `$`

`direnv dotenv` expands values the way a shell would, so an unquoted `$` and
the word after it are treated as a variable reference. The variable is
almost never set, so the reference expands to nothing and the value is
**silently truncated** — sops decrypted it correctly, `use_sops` returns 0,
and direnv reports success:

```
plaintext:          DB_PASSWORD=P4ss$word
sops decrypts to:   DB_PASSWORD=P4ss$word
environment gets:   DB_PASSWORD=P4ss
```

Single-quote the value in the plaintext, before encrypting. Verified through
a full sops round trip:

```dotenv
DB_PASSWORD='P4ss$word'
```

Double quotes do **not** work *for this one* — `"P4ss$word"` truncates exactly
like the bare form, because the expansion happens before the quotes are
stripped.

`#` fails the same way and is more likely still, since it is in every
generated-password character set:

```
plaintext:          DB_PASSWORD=P4ss#word
sops decrypts to:   DB_PASSWORD=P4ss#word
environment gets:   DB_PASSWORD=P4ss
```

Here double quotes *do* survive — which is exactly why you should not learn
the double-quote rule. **Single-quote every value.** It is the only form that
holds for both characters, and the only one you do not have to think about.

Nothing warns about this. The symptom is a service failing to authenticate
with a password that is right in the bundle and wrong in the environment, so
it surfaces a long way from its cause. Generated passwords are the usual way
to meet it: `$` is in most "special character" sets.

### Secrets are applied with `declare -gx`, not `export`

`direnv dotenv` emits `export NAME=VAL` for every key in a bundle, and bash's
`local` is dynamically scoped: an `export` run inside a function writes the
nearest enclosing frame's slot whenever some caller declared that name
`local`, and that slot is destroyed when the frame returns. Six such names
belong to direnv itself and cannot be kept clear from a fragment:

| frame | names |
|---|---|
| `use()` | `cmd` |
| `source_env()` | `rcpath`, `REPLY`, `rcpath_dir`, `rcpath_base`, `rcfile` |

`REPLY` and `cmd` are plausible names for a real secret, and a bundle key that
collides with one of them would reach `use_sops`, decrypt, and then be dropped
on the way out: no value in the environment, `use_sops` returning 0, and
direnv's success line listing only the keys that made it.

`use_sops` therefore rewrites each emitted statement to `declare -gx
NAME=VAL`, which assigns at global scope where no enclosing frame can capture
it. It has to be that one command — `declare -g NAME` followed by `export
NAME=VAL` writes the caller's slot exactly as a bare `export` does.

**Do not name a secret `REPLY` anyway.** The rewrite gets it into the
environment, and that is the problem: `REPLY` is where bash puts the result of
a `read` with no variable name, and of a `select`. Any such `read` in any
function the shell later runs overwrites it — and because the value is now
*exported*, the wrong one propagates to every child process:

```
export REPLY=SECRET; read <<< clobbered; printenv REPLY   →  clobbered
```

Bash-completion functions call bare `read` routinely, so this is not exotic:
the secret loads correctly, works for a while, and then quietly turns into
some unrelated string — the same wrong-but-plausible-value failure as [an
unquoted `$` or `#`](#quote-values-containing-), and no rewrite can prevent
it. Only the name can. The other five names above are shell-neutral and are
safe to use as keys.

That rewrite is a parse rather than a substitution, because `direnv dotenv
bash` emits one line of `;`-separated statements and spells both names and
values three ways: bare when it considers every byte safe (uppercase letters,
digits and `_ - . , / @` among them), `''` for the empty string, and a
`$'...'` literal otherwise. So a lowercase key arrives quoted, `export
$'cmd'=$'v';`, and an uppercase one does not.

Inside a `$'...'` literal a backslash escapes the character after it — `\'`
and `\\`, but also `\n`, `\t`, `\r` and `\xNN`, since direnv will not emit
those bytes raw — and an unescaped `'` closes it. Nothing else in there is
escaped, which leaves a value free to carry a raw `;`, or the literal text
`export`:

```
plaintext:      SEMI='a;export EVIL=pwned;b'
direnv emits:   export SEMI=$'a;export EVIL=pwned;b';
```

Splitting that on `;`, or replacing every `export `, corrupts the value.
`_sops_globalize` instead walks the statements, skipping each quoted literal
by its own closing rule, and copies name and value bytes through untouched —
the only edit is each statement's leading keyword. The two quoted forms need
separate rules and cannot share one: a `$'...'` closes at the first `'`
preceded by an even-length run of backslashes, whereas a POSIX `'...'` has no
escapes at all, so `'a\'` is a complete value ending in a backslash. direnv
emits `''` only for the empty string today, which makes the difference
unobservable — which is why it is written down rather than left to be
rediscovered.

Whitespace between the pieces is skipped rather than required to be absent.
direnv emits exactly one space after `export` and nothing around the `;`, but
a value can only ever carry whitespace inside a quoted literal, so tolerating
it costs nothing in safety and keeps a purely cosmetic reformatting of
direnv's output from disabling the secrets layer on an upgrade. Whitespace
around the `=` is still rejected, because `export A = 1` is a different
command rather than a differently formatted one.

A dump that still does not fit the grammar is refused (`unrecognized direnv
dotenv output`, non-zero return) rather than guessed at. Note what that
refusal looks like from outside: `use_sops` returns 1, the error prints, and
direnv still exits 0 — the shell loads with **no secrets at all**, and the
message appears only on the reload that re-evaluates the `.envrc`, not on
later `cd`s into the tree. Loud beats corrupting a value quietly, but it is
not loud on every entry.

Two constraints are left, and both are direnv's rather than bash's, because
`direnv dotenv` accepts keys that bash will not assign to:

- **Not identifiers.** `a.b` and `1a` among them. These reach `declare` and
  are rejected as `not a valid identifier` on stderr, exactly as `export`
  rejects them.
- **Identifiers bash reserves.** `UID`, `EUID`, `PPID`, `BASHPID` and
  `SHELLOPTS` are readonly, so `declare -gx UID=1` fails with `readonly
  variable` — again exactly as `export UID=1` does. `IFS` and `PATH` are not
  readonly and so are worse: they are accepted and applied, and an exported
  global `IFS` changes word splitting for the remainder of that direnv
  evaluation.

Either way the failure is per-key rather than fatal, because every statement
runs in one `eval`: the bad key prints its error, every other key still
loads, and `eval` reports the status of the *last* statement it ran. So
`use_sops` returns non-zero only when the bad key happens to be the last one
emitted — and the emission order is neither the bundle's order nor a stable
one, since direnv iterates a Go map and Go randomizes that per run. The same
bundle therefore reports success or failure at random from one reload to the
next while loading exactly the same secrets. Fix the key; do not read
`use_sops`'s exit status as a check on the bundle.

### One concatenated bundle

Each `use_sops` spawns a sops process, and that spawn is almost the whole
cost. Measured with sops 3.13.3, median of 7 runs, keys and gpg-agent warm:

| | one bundle | 8 bundles | per extra bundle |
|---|---|---|---|
| age | 23 ms | 171 ms | 20 ms |
| PGP | 36 ms | 272 ms | 33 ms |

Decrypting one bundle costs the same whether it holds 1 key or 8 — the cost
is per *invocation*, not per secret. A bare sops process with no crypto at
all is 22 ms, so age decryption is about 1 ms of real work and PGP about 14
ms. The gpg-agent round trip is therefore a minor term, not the driver; its
expensive part is starting the agent (~28 ms), and that is once per session
rather than once per bundle.

**The break-even is three to four sources.** Below that, concatenating saves
20–35 ms per reload, which nobody perceives, and costs you a build step and
everything under [Not done yet](#not-done-yet). At eight sources it saves
150–240 ms on every reload — and a reload fires on every `cd` into the tree,
so that is the difference between instant and laggy. Concatenate when you
have many sources; keep separate bundles when you have two.

`.envrc.secrets.template` carries the commented `use sops_if_exists` line for
the concatenated bundle and points here; the recipe below is the only copy.

Encrypted sops files cannot be concatenated — each carries its own metadata
and MAC, so feeding two bundles to one `sops --decrypt` fails with a
`Duplicate value` unflattening error. The merge has to happen on the
plaintext, encrypted once. Piping keeps the merged plaintext off disk:

```sh
bundle=.envrcs/.env.secrets.concatenated.sops-encrypted
cat a.env b.env |
  sops --encrypt --pgp "$FPR" --input-type dotenv --output-type dotenv /dev/stdin \
  > "$bundle.tmp" &&
  mv "$bundle.tmp" "$bundle"
```

sops has no `--stdin` flag, and bare `sops --encrypt` fails with `no file
specified` despite its help text, so `/dev/stdin` must be named explicitly.
`--input-type`/`--output-type` matter because there is no filename extension
to sniff: without them sops succeeds but writes a JSON/binary bundle that
`use_sops` cannot parse.

The recipient must be named — `--pgp <fingerprint>`, or `--age <public key>`
as the demo bundle uses. There is no `.sops.yaml` here, but sops searches
upward from the **current directory**, not the repo root, so a `~/.sops.yaml`
will supply creation rules and the encrypt will quietly succeed against
whatever recipients that file names.

A creation rule with no `path_regex` matches *every* input path, `/dev/stdin`
included — which is exactly the shape a personal `~/.sops.yaml` tends to
have, and why this recipe appears to work without a recipient flag until
someone runs it on a machine without that file. Naming the recipient is what
makes the result depend on the command rather than on where you ran it.

Write through `.tmp` and `mv`: `>` creates the output file before sops runs,
so a failed encrypt would otherwise leave a truncated bundle that
`use_sops_if_exists` treats as existing and fails to decrypt on every reload.
The `.tmp` name stays ignored — `.envrcs/.env.*` matches it and
`!*.sops-encrypted` does not re-include it.

Plaintext sources are ignored (`.env`, `*.env`, `.envrcs/.env.*`); the
encrypted bundle is not (`!*.sops-encrypted`). Committing the bundle is what
lets a fresh clone reach a working environment without first obtaining the
plaintext by some other channel.

Do not add `set -x` while debugging this fragment: bash traces `eval` *after*
expansion, so the decrypted assignments land in stderr on every reload.

### Per-call secrets: `sops_wrap`

`use_sops` exports a bundle into the environment, and the environment is
copied into every process the shell starts — an agent's Bash tool included,
where an `env | grep` has put tokens into transcripts more than once. For a
secret only one command needs, `sops_wrap` keeps it out of the environment:

```sh
sops_wrap [--set NAME=VALUE ...] <tool> <bundle> ENV=KEY [KEY ...]
```

links `$(direnv_layout_dir)/sops-bin/<tool>/<tool>` to the tracked
`sops-exec`, writes the bundle path, the `ENV=KEY` map and the `--set`
values to `.sops-wrap` beside the link, and `PATH_add`s that directory.
Each call decrypts each listed `KEY` with
`sops --decrypt --extract`, so no other key of the bundle leaves sops, sets it
as `ENV` (`KEY` alone means `KEY=KEY`), and `exec`s the real `<tool>`. The
shell never holds the value, so no listing of its environment can show it.
Each `--set` is a plain value baked into the wrapper and set on every call,
for a setting the secret must never go out without — `.envrc.kata`, the one
caller here, bakes in the server its token belongs to. A listed key missing
from the bundle fails `sops_wrap` and wires nothing. That check reads key
names, which a sops dotenv bundle keeps in plaintext, so a reload decrypts
nothing for `sops_wrap`; a bundle that does not decrypt fails per call.

**What it does not do.** Anyone with your uid and your unlocked gpg-agent can
still run `sops --decrypt` on the bundle, or read `/proc/<pid>/environ` while
the tool runs, and the tool's own children inherit the value. The wrapper
narrows accidents, not adversaries. It exports the values with the shell
builtin rather than `env NAME=value tool`: argv, unlike the environment, is
readable by every user on the host through `/proc/<pid>/cmdline` and `ps`.

**Where the wrapper lives.** The code is `.envrcs/sops-exec`, tracked; only
the link and its `.sops-wrap` data are per-checkout, in the layout dir,
because they hold neither a secret nor a GC root: each reload rewrites the
data, `rm -rf .direnv` plus a reload rebuilds both, and a worktree builds its
own on `direnv allow` with no `.worktree-symlinks` entry for them; an
untracked bundle still needs one. Each tool gets its own directory, and only
the directories wired this reload are on PATH, so a tool you stop wrapping
drops off PATH on the next reload. The bundle is always named — never the
`use_sops` default — and stored absolute, so the wrapper works from a
directory direnv never loaded. The directories and data are owner-only:
nothing secret, but an executable first on PATH. That is no stronger than
the checkout's own permissions: whoever can write `.direnv` or the checkout
can replace `sops-bin`, as they could `.envrc`.

**Order.** `PATH_add` prepends, so call `sops_wrap` after whatever brings the
tool onto PATH — `.envrc.kata` after `.envrc.user.kenn`. The wrapper finds
the real tool by walking PATH past this checkout's wrapper (by inode) and
any other checkout's (by the marker line `sops-exec` carries), so order
decides which one the shell sees, not which one the wrapper runs. The end
of every reload checks it: for each tool wrapped that reload, the root
`.envrc` logs an error if the tool no longer resolves to its wrapper —
something sourced later put the real one ahead — and names the fix. It
reports and leaves PATH as it is.

**Cold gpg cache without a terminal.** gpg hands the passphrase prompt to
whatever `GPG_TTY` names, and an agent's Bash tool inherits the `GPG_TTY` of
the terminal that launched it, so a cold cache would draw a prompt there and
wait forever. When no fd is a tty, every sops call here — `use_sops` at
reload and the wrapper per call — runs gpg through `sops-gpg-no-pinentry`,
which adds `--pinentry-mode error` to your own `SOPS_GPG_EXEC` (default
`gpg`), so a cold cache fails in milliseconds. One function, `_sops_pick_gpg`
in `sops-exec`, makes that choice for all of them, from outside any `$(...)`,
where stdout would always look like a pipe. The fix it names: run the tool
once in a terminal, which warms the cache for the agent shells after it. A
`use`d bundle under the same key warms it at every terminal reload.

**Quotes.** sops stores dotenv values verbatim, quotes included, where
`direnv dotenv` strips and expands them. The wrapper strips one matching pair
of `'` or `"` and does nothing else, so a value single-quoted per
[the rule above](#quote-values-containing-) reaches the tool exactly as
`use_sops` delivers it — and an unquoted `$` is not truncated.

**Keep per-call keys out of ambient bundles.** A bundle that is also `use`d
exports every key it holds, and the wrapper changes nothing about that. Put
ambient and per-call keys in separate bundles.

**Cost.** One sops call per distinct key per call of the tool: 160 ms with a
warm agent for a PGP bundle, measured here, about 30 ms for age; two env
names from one key cost one decrypt.

## nix

`.envrc.nix-config` pins nix-direnv and is sourced by `.envrc.user.flake`.
nix-direnv watches `flake.nix`/`flake.lock` but not the modules they import,
so edits to those do not invalidate the cached devShell. The fix is an
explicit `watch_file`, which the fragment carries commented out — this repo
ships no nix files, so the line is documentation until it does. Its paths are
relative to `.envrcs/`, e.g. `watch_file ../nix/{commands,packages}.nix`.

PWD is the recurring hazard here. `.envrc.user.flake` runs with PWD at
`.envrcs/`, and nix-direnv derives three separate things from it — the flake
expression, the layout dir, and the body of the generated
`nix-direnv-reload` helper. None of the three fails loudly: nix itself
searches upward and builds the right flake, so a bare `use flake` *works*
while watching the wrong lock file. The fragment passes `$direnv_root`
explicitly *and* runs from it; the comment on those lines says what each one
costs. The layout dir is the root `.envrc`'s job: it asks `direnv_layout_dir`
once, from the root, and pins the function to the answer. So a direnvrc that
keys layouts on `$PWD` (the direnv wiki's `~/.cache/direnv/layouts/` recipe)
cannot give a fragment that stays in `.envrcs/` a second, `--envrcs`-keyed
layout dir whose `{nix,flake}-profile*` GC roots nothing ever cleans up.
Pulling the new `.envrc` does not remove dirs already created that way:
delete `~/.cache/direnv/layouts/*--envrcs` once.

## kenn

`.envrc.user.kenn` puts the kenn-io toolkit — the tool stack the
devcontainer image ships — on PATH on the host. Opt in by adding (or
uncommenting) `source_env .envrc.user.kenn` in `.envrc.user`; it layers on top of either toolchain fragment, or on
none.

**A PATH layer, not `use flake`.** nix-direnv's `use flake`/`use nix`
delete `{nix,flake}-profile*` in the layout dir on every cache miss, and all
fragments share one layout dir (the root `.envrc` pins it), so a second `use flake` beside
`.envrc.user.flake` evicts the other's cache on every load (nix-direnv 3.0.5:
both print `Renewed cache`). `nix build --out-link kenn-toolkit` + `PATH_add`
sits outside that glob and doubles as the GC root.

**The link lives at `$direnv_root/.direnv/kenn-toolkit`**, not under
`$(direnv_layout_dir)`. With stock direnv the two are the same place. They
differ under a direnvrc that relocates layouts (the common recipe that moves
them to `~/.cache/direnv/layouts/`). There the link, and with it the GC
root, would land in a cache dir that nothing removes when the checkout or
worktree is deleted, keeping every toolkit it ever built alive. The
`use flake` profile is exposed to the same thing, but there the relocation
is the direnvrc's own choice and applies to every repo. The kenn link is
this template's, so it stays in the checkout.

**Pinned.** `kenn.rev` holds one full devcontainer commit, and the fragment
builds `github:xorq-labs/devcontainer/<rev>?dir=nix/kenn`. The pin lives in
a file rather than in the fragment so that anything else needing the same
toolkit — CI, say — can read the same revision. An empty or missing
`kenn.rev` is an error, not a fall back to devcontainer's default branch.
To try an upgrade before moving the pin, export `KENN_REV` (a commit, tag, or
slash-free branch); it persists across reloads until unset:

```sh
export KENN_REV=main; direnv reload   # try it
unset KENN_REV; direnv reload         # back to the pin
```

A bump is a change to `kenn.rev` alone. The file is watched, so moving it
rebuilds on the next load.

**If a build fails** — offline, or GitHub unreachable — the fragment keeps
the previously built toolkit and says so. The layer comes up empty, with a
`log_error`, only when nothing has been built yet or the pin is empty.

**Free by default.** `kenn-io-toolkit-all` adds `kenn-forge` (Elastic-2.0,
unfree; the flake's own `allowUnfreePredicate` covers it, so switching
`kenn_attr` is the whole change). That is a licensing call, so it is not the
default.

It needs `nix` with network access to GitHub on the first load, and nothing
else: no devcontainer checkout, and no nix-direnv. There is no cache: every
load re-evaluates the flake (a few seconds), offline after the first.

## kata

`.envrc.kata` points kata at a team server: it exports `KATA_SERVER` from
`KATA_TEAM_SERVER`, sets `KATA_TRUST_PRIVATE_NETWORK=1`, unsets
`KATA_ALLOW_INSECURE`, and wraps kata with
[`sops_wrap`](#per-call-secrets-sops_wrap) so the token never enters the
environment. Opt in with `source_env .envrc.kata` in `.envrc.user` (a file
older than this fragment lacks the commented line: add it), after
`.env.local` for the server (the literal tailnet IP, in 100.64.0.0/10, not a
name) and after the kenn layer, which brings the kata binary the wrapper
runs.

The token is the `KATA_TEAM_TOKEN` key of a sops bundle:
`.envrcs/.env.secrets.kata.sops-encrypted`, or the one `kata_team_bundle`
names in `.envrc.secrets`. Do not also `use` that bundle — see
[the ambient rule](#per-call-secrets-sops_wrap).

A token that an earlier version of this fragment read from an ambient bundle
moves out of it into this one; leaving it there is what the ambient rule
forbids, and the fragment unsets it anyway.

**Two names out, both per call.** The wrapper sets `KATA_AUTH_TOKEN`, which
a `KATA_SERVER` route reads, and `KATA_TEAM_TOKEN`, which a daemon catalog
entry in `~/.kata/config.toml` names with `token_env`, so `kata --daemon
team` works too. It also sets `KATA_SERVER` and
`KATA_TRUST_PRIVATE_NETWORK` itself (`--set`), so the token never goes out
without the server it belongs to, whatever the caller did to `KATA_SERVER`.
Neither token name is left in the shell: the fragment unsets both
whether or not it wired anything, because one inherited from outside would
bypass the wrapper, and `KATA_AUTH_TOKEN` overrides every daemon's token.

**An `if`, not `${VAR:?}`.** A failing `:?` makes direnv drop everything
the `.envrc` sets, the kenn PATH included. Here a missing server or a
`sops_wrap` failure logs an error, sets nothing, and kata picks its daemon as
it would anywhere else.

**No URL check.** kata 0.18.0 refuses a `KATA_SERVER` with no scheme,
another scheme, or plain http to a name or a public IP, before connecting; a
well-formed URL to the wrong host passes kata and any pattern check alike.
The refusal suggests `KATA_ALLOW_INSECURE=1`: fix the value instead, since
that is the variable the fragment removes.

**Checking it.** `command -v kata` names `.direnv/sops-bin/kata/kata`, and
`compgen -e | grep -cx 'KATA_\(AUTH\|TEAM\)_TOKEN'` is 0. `kata federation identity --json` sends the
token and reports the actor it authenticated; `kata health` sends none, so it
passes even where the token would be refused.

## Path conventions

- **`$direnv_root`** — exported by the root `.envrc`; points to the repo root. Use it for paths that must survive worktree copies (e.g. `$direnv_root/.venv`), and for anything a helper would otherwise resolve against PWD (e.g. `use flake "$direnv_root"`).
- Fragment-relative names (`source_env .envrc.sops`, `dotenv_if_exists .env.local`) resolve against `.envrcs/` itself, so bare names work between fragments.

Prefer these over bare relative paths like `../.venv`, which break when the
evaluation directory isn't what you expect.

## Adopting this layout in another repo

Everything above describes this repo. Adopting the layout elsewhere is a
different job, and these are its edges.

**Prerequisites.** `direnv` always. `sops`, plus whatever key backend your
bundles use, only if you keep the secrets layer — and note that a missing
`sops` fails *quietly*: the fragment logs `sops: command not found` and
`sops --decrypt failed for ...`, the load continues, and nothing else
complains. `uv` or `nix` only if you enable that toolchain fragment.

**What to copy.** The root `.envrc`, `.gitignore.template`, and all of
`.envrcs/` except `demo-age-key.txt` and `.env.secrets.demo.sops-encrypted`
— those two exist so *this* repo demonstrates itself. Leaving them out is
safe: the demo line in `.envrc.secrets.template` watches a bundle that isn't
there and no-ops. The templates are optional too: leave out
`.envrc.secrets.template` (with `.envrc.sops`, `sops-exec`, `sops-gpg-no-pinentry` and the demo files) if you have
no sops secrets, or `.gitignore.template` if you already keep a
`.gitignore` of your own — see
[Auto-create](#auto-create-and-how-to-disable-a-fragment).

**Fix your `.gitignore` before the first `direnv allow`, not after.** The
auto-create skips an existing `.gitignore`, so `.envrcs/.envrc.secrets` and
`.envrcs/.envrc.user` are stageable from the moment they are created. Three
things to do, in this order:

1. Add the block from [Untracked](#untracked-local--secret) **at the end of
   your file**. "The negations come last" means last overall, not last within
   the block — a later `.env*` of your own will re-ignore
   `.envrcs/.env.*.template` and your committed bundle.
2. Remove any existing rule that ignores `.envrc`. It is a common one, and
   this layout needs the root `.envrc` tracked.
3. Check, rather than assume:
   ```sh
   git check-ignore -v .envrc .envrcs/.env.local.template \
       .envrcs/.env.secrets.demo.sops-encrypted .envrcs/.envrc.secrets
   ```
   The first three should print nothing. The last should be ignored.

**If you already have an `.envrc`**, its contents move into the root `.envrc`
*after* the `export direnv_root` line and *before* the `source_env` calls, or
into a fragment of your own sourced alongside them. `$direnv_root` and the
layout-dir lines have to run before anything uses them.

**The tracked templates are placeholders, not content.** `.env.local.template`
ships `EXAMPLE_*` names; `.envrc.secrets.template` ships the demo bundle line
with its `SOPS_AGE_KEY_FILE=` prefix. Rewrite both for your project before
your team clones — the generated copies are never overwritten afterwards,
so a template fix does not reach a checkout that already has one. Whoever
needs it has to delete their generated file and reload.

## Not done yet

Recorded here rather than in a tracker so it survives a clone.

**A generator for the concatenated bundle** — worth building only past the
break-even above. The recipe is written out but nothing runs it, so the
concatenated shape is a thing you assemble by hand every time.

Whatever builds it must **reject duplicate keys rather than resolve them**.
Concatenating two sources that both define `DATABASE_URL` produces a bundle
sops encrypts without complaint and `direnv dotenv` reads last-wins, so which
value you get depends on the order the sources were listed and nothing reports
it. That is a wrong-but-plausible secret — the same failure shape as
[an unquoted `$` or `#`](#quote-values-containing-).

**An example plaintext source** for that generator. It needs a name the ignore
rules tolerate: everything matching `.env`, `*.env` or `.envrcs/.env.*` is
ignored, and only `*.sops-encrypted` is re-included, so an example input has
to live outside those patterns or be explicitly negated.

**`sops_wrap` for age bundles whose key file is not ambient.** The wrapper
calls sops with the caller's environment, so an age bundle works when
`SOPS_AGE_KEY_FILE` is exported (or the key sits at sops's default path), but
the demo's one-call `SOPS_AGE_KEY_FILE=... use ...` prefix has no equivalent:
`sops_wrap` would need to bake the key file path into the wrapper.

Deliberately not done, so they are not mistaken for oversights:

- The nix `watch_file` in `.envrc.nix-config` stays commented out until this
  repo has nix files worth watching.
- **No staleness detection between a concatenated bundle and its sources.**
  When one source changes, nothing tells you the bundle is out of date: the
  bundle itself is watched, so direnv reloads when the bundle changes, but not
  when its inputs do. If the sources are committed as individual
  `*.sops-encrypted` files the drift is invisible, because both sides are
  ciphertext. Accepted rather than solved — and a check could not run in CI
  regardless, since verifying the two agree means decrypting both, so it could
  only ever be a local hook or a habit.
- **No `.sops.yaml`.** Creation rules would not shorten the recipe anyway:
  sops matches them against the *input* path, and the recipe's input is
  `/dev/stdin`, so a rule keyed on the bundle's name never fires. Naming the
  recipient on the command line is one flag, and it makes the result depend
  on the command rather than on where it was run.

## How it fits together

```
.envrc (repo root)
├── export direnv_root
├── auto-create .gitignore, .envrcs/.envrc.{secrets,user} if missing
├── source_env_if_exists .envrcs/.envrc.secrets
│   └── .envrc.sops → use_sops on encrypted .env files; defines sops_wrap
└── source_env_if_exists .envrcs/.envrc.user
    ├── one of: .envrc.user.{uv,flake}
    ├── optionally also: .envrc.user.kenn → kenn-io toolkit on PATH
    ├── dotenv_if_exists .env.local → per-user non-secret values, if configured
    └── optionally: .envrc.kata → kata calls to the team server,
                                  token per call via sops_wrap
```

A fresh clone only needs:

```sh
direnv allow
```

To also set per-user non-secret values (optional, not auto-created):

```sh
cp .envrcs/.env.local.template .envrcs/.env.local
# edit .envrcs/.env.local, uncomment at most ONE strategy
```
