# git + delta pager. Shared base: user.email is mkDefault so each consumer
# overrides it at normal priority. helix ships in both consumers' shared CLI
# set, so core.editor = "hx" unconditionally.
{ lib, pkgs, ... }:
{
  programs.git = {
    enable = true;
    package = lib.mkDefault pkgs.gitFull;
    signing.format = null;
    lfs.enable = true;
    ignores = [
      ".direnv"
      "result"
      ".jj"
    ];
    settings = {
      alias.lg = "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all";
      user.name = "Corentin AZAIS";
      user.email = lib.mkDefault "azaiscorentin@gmail.com";
      core.editor = "hx";
      init.defaultBranch = "main";
      merge.conflictStyle = "zdiff3";
      commit.verbose = true;
      diff.algorithm = "histogram";
      log.date = "iso";
      column.ui = "auto";
      branch.sort = "committerdate";
      push.autoSetupRemote = true;
      rerere.enabled = true;
      pull.rebase = true;
      rebase.autoStash = true;
    };
  };

  # `programs.delta` is its own top-level home-manager module in 26.05;
  # `programs.git.delta.*` was renamed away. `enableGitIntegration` must
  # be set explicitly now — implicit auto-enable is deprecated.
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      line-numbers = true;
    };
  };
}
