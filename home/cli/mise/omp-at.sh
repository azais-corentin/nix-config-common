# shellcheck shell=bash
# omp-at: run oh-my-pi from source at any git version (PR, branch, tag, commit,
# or several stacked with '+'), using the local clone. Each spec gets a
# disposable detached worktree under $XDG_CACHE_HOME/omp-at. The toolchain is
# that version's own Nix dev shell; JS deps reinstall only when the tree
# changes; Rust natives rebuild only when their inputs change (content-keyed,
# shared across worktrees, incremental cargo target).

repo=${OMP_AT_REPO:-$HOME/dev/oh-my-pi}
remote=https://github.com/can1357/oh-my-pi.git
cache=${XDG_CACHE_HOME:-$HOME/.cache}/omp-at

log() { printf 'omp-at: %s\n' "$*" >&2; }
die() {
  log "$*"
  exit 1
}

usage() {
  cat <<'EOF'
usage: omp-at <spec> [omp args...]
       omp-at --clean
       omp-at --help

Runs oh-my-pi from source at <spec> using the clone at $OMP_AT_REPO
(default ~/dev/oh-my-pi). Every run fetches the newest commit of each selector.

<spec> is one selector, or several joined by '+': the first is checked out and
each following one is merged on top, in order.

selectors:
  14456, #14456, https://github.com/can1357/oh-my-pi/pull/14456   PR head
  main, any branch name                                           branch tip
  v18.6.2, any tag                                                tag
  8aaf115b8e, any commit SHA                                      commit
A bare number is always a PR. Requires oh-my-pi >= v17.3.0.

examples:
  omp-at 14456
  omp-at main --resume
  omp-at main+14456+14470 -p 'hello'

--clean removes every omp-at worktree, refs/omp-at/* and all build caches.
EOF
}

have_repo() { git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; }

lock() {
  mkdir -p "$cache"
  exec 9>"$cache/lock"
  flock 9
}

clean() {
  lock
  if have_repo; then
    local wt
    for wt in "$cache"/worktrees/*; do
      if [ -d "$wt" ]; then
        git -C "$repo" worktree remove --force "$wt" >&2 || rm -rf "$wt"
      fi
    done
    git -C "$repo" worktree prune
    git -C "$repo" for-each-ref --format='delete %(refname)' refs/omp-at/ |
      git -C "$repo" update-ref --stdin
  fi
  rm -rf "$cache/worktrees" "$cache/natives" "$cache/devshell" "$cache/cargo-target"
  log "removed worktrees, refs/omp-at/* and caches"
}

if [ $# -eq 0 ]; then
  usage >&2
  exit 2
fi
case $1 in
  -h | --help)
    usage
    exit 0
    ;;
  --clean)
    clean
    exit 0
    ;;
  -*)
    usage >&2
    die "unknown option: $1"
    ;;
esac
spec=$1
shift

have_repo || die "no oh-my-pi clone at $repo (set OMP_AT_REPO, or: git clone $remote $repo)"
case $spec in
  +* | *+ | *++*) die "empty selector in spec: $spec" ;;
esac
IFS=+ read -r -a selectors <<<"$spec"

pr_number_re='^#?([0-9]+)$'
pr_url_re='^https://github\.com/can1357/oh-my-pi/pull/([0-9]+)([/?#].*)?$'
sha_re='^[0-9a-f]{7,40}$'

slugs=()
revs=()
refspecs=()
for sel in "${selectors[@]}"; do
  pr=
  if [[ $sel =~ $pr_number_re ]] || [[ $sel =~ $pr_url_re ]]; then
    pr=${BASH_REMATCH[1]}
  elif [[ $sel == *://* ]]; then
    die "only https://github.com/can1357/oh-my-pi/pull/<N> URLs are supported: $sel"
  fi
  if [ -n "$pr" ]; then
    slug=pr-$pr
    src=refs/pull/$pr/head
  else
    slug=${sel//[^A-Za-z0-9._-]/-}
    src=$sel
  fi
  slugs+=("$slug")
  if [ -z "$pr" ] && [[ $sel =~ $sha_re ]] && git -C "$repo" rev-parse -q --verify "$sel^{commit}" >/dev/null; then
    revs+=("$sel")
  else
    revs+=("refs/omp-at/$slug")
    refspecs+=("+$src:refs/omp-at/$slug")
  fi
done

lock
mkdir -p "$cache/worktrees" "$cache/natives" "$cache/devshell"

if [ ${#refspecs[@]} -gt 0 ]; then
  log "fetching $spec"
  git -C "$repo" fetch --quiet --no-tags "$remote" "${refspecs[@]}" || die "fetch failed for $spec"
fi
commits=()
for rev in "${revs[@]}"; do
  commits+=("$(git -C "$repo" rev-parse --verify "$rev^{commit}")")
done

name=$(
  IFS=+
  printf '%s' "${slugs[*]}"
)
wt=$cache/worktrees/$name
if ! { [ -f "$wt/.git" ] && git -C "$wt" rev-parse -q --verify HEAD >/dev/null; }; then
  rm -rf "$wt"
  git -C "$repo" worktree prune
  log "creating worktree $wt"
  git -C "$repo" worktree add --quiet --detach "$wt" "${commits[0]}" >&2
fi
gitdir=$(git -C "$wt" rev-parse --absolute-git-dir)
stamp() { cat "$gitdir/omp-at-$1" 2>/dev/null || true; }

inputs="${commits[*]}"
if [ "$(stamp inputs)" != "$inputs" ]; then
  rm -f "$gitdir/omp-at-inputs"
  git -C "$wt" checkout --quiet --detach --force "${commits[0]}"
  for ((i = 1; i < ${#commits[@]}; i++)); do
    if ! git -C "$wt" -c user.name=omp-at -c user.email=omp-at@localhost \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null \
      merge --quiet --no-ff --no-edit -m "omp-at: merge ${selectors[i]}" "${commits[i]}" >&2; then
      git -C "$wt" merge --abort || true
      die "${selectors[i]} does not merge cleanly onto ${selectors[*]:0:i}"
    fi
  done
  printf '%s\n' "$inputs" >"$gitdir/omp-at-inputs"
fi
log "$name at $(git -C "$wt" log -1 --format='%h %s')"

for f in flake.nix nix/dev-shell.nix; do
  git -C "$wt" cat-file -e "HEAD:$f" 2>/dev/null || die "$name has no $f; omp-at needs oh-my-pi >= v17.3.0"
done

# Content key over HEAD's git object ids for the given paths ('-' if absent).
key_of() {
  local p
  for p in "$@"; do
    git -C "$wt" rev-parse -q --verify "HEAD:$p" || echo -
  done | sha256sum | cut -c1-16
}

# Dev shell: evaluate only the files devShells.default reads, so the 210 MB
# tree is never copied to the store. --profile records the env and makes it a
# GC root, which also keeps the store paths in the natives' RPATH alive.
shell_key=$(key_of flake.nix flake.lock rust-toolchain.toml nix)
shell_dir=$cache/devshell/$shell_key
if ! { [ -s "$shell_dir/env" ] && [ -e "$shell_dir/profile" ]; }; then
  log "evaluating dev shell $shell_key"
  rm -rf "$shell_dir"
  mkdir -p "$shell_dir/src"
  git -C "$wt" archive HEAD flake.nix flake.lock rust-toolchain.toml nix | tar -x -C "$shell_dir/src"
  # shellcheck disable=SC2016 # expanded inside the dev shell
  nix develop --profile "$shell_dir/profile" "path:$shell_dir/src" \
    --command bash -c 'command -v bun; printf "%s\n" "${LD_LIBRARY_PATH:-}"' >"$shell_dir/env.tmp"
  mv "$shell_dir/env.tmp" "$shell_dir/env"
fi
{
  read -r bun_path
  read -r native_libs || true
} <"$shell_dir/env"
if [ ! -x "$bun_path" ]; then
  rm -rf "$shell_dir"
  die "stale dev shell cache $shell_key removed; re-run"
fi
in_shell() { nix develop "$shell_dir/profile" --command "$@"; }

tree=$(git -C "$wt" rev-parse 'HEAD^{tree}')
if [ "$(stamp installed)" != "$tree" ]; then
  log "installing JS dependencies"
  (cd "$wt" && in_shell bun install) >&2
  printf '%s\n' "$tree" >"$gitdir/omp-at-installed"
fi

natives_key=$(key_of crates Cargo.toml Cargo.lock .cargo rust-toolchain.toml flake.lock \
  packages/natives/package.json packages/natives/scripts)
natives_dir=$cache/natives/$natives_key
native_dest=$wt/packages/natives/native
if [ "$(stamp natives)" != "$natives_key" ]; then
  rm -f "$native_dest"/*.node
  cached=("$natives_dir"/*.node)
  if [ -e "${cached[0]}" ]; then
    log "using cached natives $natives_key"
    for f in "${cached[@]}"; do
      ln -f "$f" "$native_dest/" 2>/dev/null || cp "$f" "$native_dest/"
    done
  else
    log "building natives $natives_key"
    (cd "$wt" && in_shell env CARGO_TARGET_DIR="$cache/cargo-target" bun --cwd=packages/natives run build) >&2
    rm -rf "$natives_dir.tmp"
    mkdir -p "$natives_dir.tmp"
    cp "$native_dest"/*.node "$natives_dir.tmp/"
    rm -rf "$natives_dir"
    mv "$natives_dir.tmp" "$natives_dir"
  fi
  printf '%s\n' "$natives_key" >"$gitdir/omp-at-natives"
fi

# Release the lock, then hand over: only bun's own bin dir goes on PATH (the
# dev launcher execs `bun` from PATH); the rest of the dev shell stays out of
# the agent's tool environment.
exec 9>&-
export PATH="${bun_path%/*}:$PATH"
export OMP_NATIVE_LIBRARY_PATH="${OMP_NATIVE_LIBRARY_PATH:-$native_libs}"
exec "$wt/packages/coding-agent/scripts/omp" "$@"
