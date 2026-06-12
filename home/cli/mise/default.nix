# mise tool/runtime manager. oh-my-pi is deliberately NOT imported here — each
# consumer wraps `cli.mise-oh-my-pi` with its own extras.
{ config, ... }:
{
  imports = [ ./jcode.nix ];
  programs.mise = {
    enable = true;
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
  programs.direnv.mise.enable = config.programs.direnv.enable;
}
