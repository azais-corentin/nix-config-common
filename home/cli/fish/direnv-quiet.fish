# Per-project silencing of direnv's own log lines.
#
# A project opts in with a `# direnv: quiet` comment in its .envrc. direnv then
# prints nothing of its own in that project — no `loading`, no `using flake`, no
# `nix-direnv: …`, no `export +VAR …` diff, no `unloading` on the way out —
# while output the .envrc itself produces (a devshell banner, say) still comes
# through. Errors stay visible: direnv formats those with its own hardcoded
# prefix, out of reach of the knob used here.
#
# The knob is an empty DIRENV_LOG_FORMAT, which turns off every status line.
# direnv 2.36+ reads that variable only when a direnv.toml exists — the lookup
# sits inside `if config.TomlPath != ""` in internal/cmd/config.go — so
# programs.direnv.config writes one.
#
# This must run before direnv's own PWD handler, and does: conf.d loads ahead of
# config.fish, where the direnv hook is installed; fish delivers an event to its
# handlers in definition order; and direnv defines its PWD handler later still,
# on the first prompt.

# Path of the nearest .envrc at or above a directory, empty if there is none.
function __direnv_quiet_rc -a dir
    while true
        if test -f $dir/.envrc
            echo $dir/.envrc
            return 0
        end
        test $dir = / && return 1
        set dir (path dirname $dir)
    end
end

function __direnv_quiet_optin -a envrc
    test -f "$envrc" && string match -qr '^#\s*direnv:\s*quiet\s*$' <$envrc
end

function __direnv_quiet_sync --on-variable PWD --description 'Silence direnv in projects whose .envrc opts in'
    set -l rc (__direnv_quiet_rc $PWD)
    if test -z "$rc" -a -n "$DIRENV_DIR"
        # Nothing to load here, but a loaded environment is about to go away.
        # Whoever loaded it decides whether its `unloading` line is printed.
        # DIRENV_DIR is the directory prefixed with a marker character.
        set rc (string sub --start 2 -- $DIRENV_DIR)/.envrc
    end
    if __direnv_quiet_optin "$rc"
        set -gx DIRENV_LOG_FORMAT ''
    else if set -q DIRENV_LOG_FORMAT
        set -e DIRENV_LOG_FORMAT
    end
    return 0
end

# A new shell starts inside its directory without a PWD change, so sync once.
__direnv_quiet_sync
