# Tern, installed beside Ghostty (the default terminal stays the consumer's
# call). Its archive is invite-only: `mise run tern:fetch` adds the pinned one
# to the store once per version on each machine.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  tern = pkgs.callPackage ./package.nix { };
  fonts = config.stylix.fonts;
in
{
  # Tern reports TERM=xterm-kitty.
  home.packages = [
    tern
    pkgs.kitty.terminfo
  ];

  # Keeps panes' programs alive between windows. Tern's own "Start at login"
  # would write an autostart entry naming the binary's store path, stale after
  # the next update.
  systemd.user.services.tern-daemon = {
    Unit = {
      Description = "Tern session daemon";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
      # Restarting kills every pane's program; the next login picks up a new
      # build.
      X-RestartIfChanged = false;
    };
    Service = {
      ExecStart = "${lib.getExe tern} daemon";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Read-only: Settings pages can't persist changes. Tern can't update itself
  # from the store, so its update checks only nag.
  xdg.configFile."tern/settings.json".text = builtins.toJSON (
    {
      auto_update = false;
    }
    // lib.optionalAttrs config.stylix.enable {
      font_family = fonts.monospace.name;
      # Tern sizes in px, stylix in pt.
      font_size = fonts.sizes.terminal * 4.0 / 3;
    }
  );
}
