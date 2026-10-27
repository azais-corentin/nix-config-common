# MCP server registry. context7 + nixos are shared; consumers add their own
# servers (the `programs.mcp.servers` attrset merges across modules).
{ config, pkgs, ... }:
let
  # nixpkgs moved python3Packages.mcp to 2.x and marked fastmcp-slim broken on
  # it; mcp-nixos still needs fastmcp, so build it against mcp 1.x.
  # TODO: drop once nixpkgs fastmcp-slim supports mcp 2.
  mcp-nixos = pkgs.mcp-nixos.override {
    python3Packages =
      (pkgs.python3.override {
        packageOverrides = final: _: { mcp = final.mcp_1; };
      }).pkgs;
  };
in
{
  programs.mcp.enable = true;
  programs.mcp.servers = {
    context7 = {
      url = "https://mcp.context7.com/mcp";
    };
    nixos = {
      command = "${mcp-nixos}/bin/mcp-nixos";
    };
  };

  home.file.".omp/agent/mcp.json".source = config.xdg.configFile."mcp/mcp.json".source;
}
