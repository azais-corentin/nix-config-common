# mise tool/runtime manager. oh-my-pi is deliberately NOT imported here — each
# consumer wraps `cli.mise-oh-my-pi` with its own extras.
{ config, pkgs, ... }:
let
  # Newer of pkgs.mise and the pinned release binary (see package.nix).
  misePackage = import ./package.nix pkgs;
in
{
  imports = [
    ./jcode.nix
    ./worktrunk.nix
  ];
  programs.mise = {
    enable = true;
    package = misePackage;
    enableZshIntegration = config.programs.zsh.enable;
    globalConfig = {
      settings = {
        experimental = true;
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
