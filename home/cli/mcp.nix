# MCP server registry. context7 + nixos are shared; consumers add their own
# servers (the `programs.mcp.servers` attrset merges across modules).
{ config, pkgs, ... }:
{
  programs.mcp.enable = true;
  programs.mcp.servers = {
    context7 = {
      url = "https://mcp.context7.com/mcp";
    };
    nixos = {
      command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
    };
  };

  home.file.".omp/agent/mcp.json".source = config.xdg.configFile."mcp/mcp.json".source;
}
