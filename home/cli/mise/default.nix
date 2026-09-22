# mise tool/runtime manager: the pinned mise, its settings, a few global tools
# and the direnv integration. Agent tools are separate features
# (`cli.codex`, `cli.worktrunk`, `cli.mise-oh-my-pi`) that import this one.
{ config, pkgs, ... }:
let
  # Newer of pkgs.mise and the pinned release binary (see package.nix).
  misePackage = import ./package.nix pkgs;
in
{
  programs.mise = {
    enable = true;
    package = misePackage;
    enableZshIntegration = config.programs.zsh.enable;
    globalConfig = {
      settings = {
        all_compile = false;
        experimental = true;
        not_found_auto_install = false;
      };
      tools = {
        "github:beaconbay/ck" = "latest";
        dprint = "latest";
        bun = "latest";
      };
    };
  };
  programs.direnv.mise = {
    enable = config.programs.direnv.enable;
    package = misePackage;
  };
}
