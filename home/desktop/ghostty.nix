# Ghostty terminal, theme-neutral. Fonts come from stylix or the consumer
# layer; the terminal-default mimeApps association is a consumer concern.
#
# Tracks Ghostty's main branch: consumers must declare a `ghostty` flake input
# (github:ghostty-org/ghostty, nixpkgs following theirs), surfaced here as
# pkgs.inputs.ghostty. Tip carries the systemd 262 notify-reload startup fix
# (ghostty-org/ghostty#14399) that 1.3.1 lacks.
{ config, pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.inputs.ghostty.default.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        # Local: GTK logs every OSC 4/10/11 colour set as an unimplemented
        # action; there is nothing for GTK to do with it.
        ./ghostty-gtk-quiet-color-change.patch
      ];
    });
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
      # io_uring keeps poll SQEs in flight, so idle event loops are counted as
      # iowait and IO pressure (PSI); epoll avoids the bogus accounting.
      async-backend = "epoll";
      # Install terminfo on SSH hosts that lack xterm-ghostty, falling back to
      # TERM=xterm-256color when that fails.
      shell-integration-features = "ssh-env,ssh-terminfo";
    };
  };
}
