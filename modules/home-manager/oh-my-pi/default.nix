# oh-my-pi (omp) declarative Home Manager module.
#
# Manages every user-level config file omp reads from ~/.omp/agent/:
#   - config.yml   (oh-my-pi.settings; typed 1:1 map of SETTINGS_SCHEMA + freeform)
#   - models.yml   (oh-my-pi.models; typed providers/models + freeform)
#   - keybindings.yml, ssh.json, AGENTS.md/SYSTEM.md/RULES.md
#   - skills/ commands/ rules/ agents/ prompts/ instructions/ themes/ tools/ hooks/
#
# mcp.json is intentionally NOT managed here — it is owned by the shared
# programs.mcp module.
{ lib, ... }:
{
  imports = [
    ./settings.nix
    ./models.nix
    ./files.nix
  ];

  options.oh-my-pi.enable = lib.mkEnableOption "oh-my-pi declarative configuration";
}
