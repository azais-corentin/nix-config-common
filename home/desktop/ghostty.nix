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
      # io_uring keeps poll SQEs in flight, so idle event loops are counted as
      # iowait and IO pressure (PSI); epoll avoids the bogus accounting.
      async-backend = "epoll";
      # Install terminfo on SSH hosts that lack xterm-ghostty, falling back to
      # TERM=xterm-256color when that fails.
      shell-integration-features = "ssh-env,ssh-terminfo";
    };
  };
}
