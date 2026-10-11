# Ghostty terminal, theme-neutral. Fonts come from stylix or the consumer
# layer; the terminal-default mimeApps association is a consumer concern.
{ config, pkgs, ... }:
{
  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        # Demotes the per-page "adjusting page capacity" log to debug.
        # TODO: drop once nixpkgs ships a Ghostty release after 1.3.1.
        (pkgs.fetchpatch {
          name = "ghostty-demote-page-capacity-log.patch";
          url = "https://github.com/ghostty-org/ghostty/commit/4144f6dea4dbf9586c797e535a04f1cfd381d8a7.patch";
          hash = "sha256-ZDd6sFgP6PIDBpLHcsz35UdUGkR2cc7Sqk2Z7t1UHa4=";
        })
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
