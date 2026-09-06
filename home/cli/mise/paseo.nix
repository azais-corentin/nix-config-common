{ lib, ... }:
{
  services.paseo.enable = true;
  programs.mise.globalConfig.tools = {
    node = lib.mkDefault "24";
    "npm:@getpaseo/cli" = {
      version = "0.7.2";
      allow_builds = [
        "esbuild"
        "node-pty"
      ];
    };
  };
}
