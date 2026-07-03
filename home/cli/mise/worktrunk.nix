# worktrunk (the `wt` git-worktree CLI) via mise's aqua backend, plus the
# fish shell integration that lets `wt switch` change the shell's directory.
#
# Fish is "wrapper-based" for worktrunk: instead of an eval line in
# config.fish, integration is a lazy-autoload stub at functions/wt.fish. Fish
# autoloads it only on the first `wt` call — after `mise activate` has put `wt`
# on PATH — so it is immune to the conf.d/config.fish ordering that would make
# an eval line a no-op (it runs before mise activation). On first call the stub
# sources `wt config shell init fish`, which redefines `wt` in-memory with the
# full integration, so worktrunk upgrades take effect without reinstalling.
{ config, lib, ... }:
{
  # aqua registry resolves `worktrunk` and extracts the `wt`/`git-wt` binaries.
  programs.mise.globalConfig.tools.worktrunk = "latest";

  # worktrunk user config: LLM commit messages + new-worktree setup. Written
  # read-only from the nix store; worktrunk only writes approvals.toml and git
  # config, never config.toml, so a symlinked config is safe.
  xdg.configFile."worktrunk/config.toml".text = ''
    # Copy gitignored files (build caches, .env, .direnv) into each new worktree.
    post-start = "wt step copy-ignored"

    # LLM commit messages for `wt merge` / `wt step commit` / `wt step squash`.
    # `omp -p` reads the prompt from an ARGUMENT, not stdin; worktrunk pipes the
    # templated prompt to stdin, so bridge it with "$(cat)". Flags keep the run
    # fast + hermetic: no session/tools/LSP/skills/rules/extensions/title/system
    # prompt; haiku + thinking off for quick one-line subjects.
    [commit.generation]
    command = "omp -p --no-session --no-tools --no-lsp --no-skills --no-rules --no-extensions --no-title --system-prompt='You write git commit messages. Explain WHY the change was made, not what changed: the diff already shows what changed, so capture the motivation, intent, or problem being solved. If the prompt tells you to describe the change and not the intent or benefit, disregard that and explain the reason instead. Use an imperative subject under 50 chars, then a body paragraph giving the rationale.' --model google-antigravity/gemini-3.1-flash-lite \"$(cat)\""
  '';

  xdg.configFile."fish/functions/wt.fish" = lib.mkIf config.programs.fish.enable {
    text = ''
      # worktrunk shell integration for fish
      # Sources full integration from binary on first use.
      # Docs: https://worktrunk.dev/config/#shell-integration
      # Check: wt config show | Uninstall: wt config shell uninstall

      function wt
          # Completion mode: let the binary emit completions directly. A stale
          # third-party completion (e.g. an old Homebrew vendor_completions.d/wt.fish)
          # may invoke the bare `wt` command with COMPLETE set; without this guard
          # that lands back on this stub and recurses. Mirrors the bash/zsh guard.
          if set -q COMPLETE
              command wt $argv
              return
          end
          command wt config shell init fish | source
          # Check both command exit code ($pipestatus[1]) and source exit code ($pipestatus[2])
          # If source fails, the function isn't replaced and we'd infinite-loop calling ourselves
          set -l wt_status $pipestatus[1]
          set -l source_status $pipestatus[2]
          test $wt_status -eq 0; or return $wt_status
          test $source_status -eq 0; or return $source_status
          wt $argv
      end
    '';
  };
}
