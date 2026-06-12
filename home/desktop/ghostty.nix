# Ghostty terminal, theme-neutral. Fonts come from stylix or the consumer
# layer; the terminal-default mimeApps association is a consumer concern.
{ config, ... }:
{
  programs.ghostty = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
    systemd.enable = true;
    settings = {
      window-padding-x = 8;
      window-padding-y = 8;
      window-decoration = false;
      background-opacity = 0.95;
      copy-on-select = false;
      mouse-hide-while-typing = true;
      cursor-style = "bar";
      adjust-cursor-thickness = "15%";
      scrollback-limit = 10000000;
      bold-is-bright = false;
    };
  };
}
