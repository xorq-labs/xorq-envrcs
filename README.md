# what

a repo to demonstrate `direnv` `.envrc` file organization

The root `.envrc` exports `$direnv_root`, then sources fragments from
`.envrcs/`: two that rebuild `.gitignore` and create the untracked local
files from their tracked templates, then the secrets and user layers. A
fresh clone needs only `direnv allow`. `tests/test-fragments.sh` tests the
first two.

## three layers

| layer | file | holds |
|---|---|---|
| secrets | `.envrcs/.envrc.secrets` | shell: which sops bundles to decrypt |
| user | `.envrcs/.envrc.user` | per-user shell logic: which toolchain to bring up |
| local | `.envrcs/.env.local` | per-user, non-secret `KEY=value` |

Each is untracked and generated from a tracked `*.template`. The first two
are created automatically on `direnv allow`; the third is copied by hand,
because its template offers mutually exclusive strategies to choose between.

Plaintext secret sources are never committed; sops-encrypted bundles are.

So that `direnv allow` really is all a fresh clone needs, the demo bundle is
encrypted to a throwaway age key committed beside it — see
[the demo key](.envrcs/README.md#the-committed-demo-key). Real bundles are
encrypted to their real recipients, whose private keys stay out of the repo.

Adopting this layout in another repo? Start at
[Adopting this layout](.envrcs/README.md#adopting-this-layout-in-another-repo)
— what to copy, the prerequisites, and the `.gitignore` edges, including
why the ignore rules have to go in before the first `direnv allow`.

See [`.envrcs/README.md`](.envrcs/README.md) for the fragment-by-fragment
reference — auto-create rules and how to disable a fragment, the sops
helpers, path conventions, and the concatenated-bundle design.

## merging

PRs are squash-merged, the only method the repo allows. The squash commit
takes the PR title and the branch's commit subjects. No CI runs yet
(kata xorq-envrcs#m9v3) and there is no pre-merge check script: run
`bash tests/test-fragments.sh` on the head before merging.
