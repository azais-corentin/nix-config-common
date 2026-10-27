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

  # The daemon hands its own WAYLAND_DISPLAY and DISPLAY to every pane, so one
  # started before login leaves them without a display. At login, restart it
  # into the session's display unless a pane's shell is running something:
  # restoring a session's layout respawns idle shells, and nothing else is lost.
  adopt = pkgs.writeShellApplication {
    name = "tern-daemon-adopt";
    runtimeInputs = [
      pkgs.gnugrep
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      displays() { grep -E '^(WAYLAND_DISPLAY|DISPLAY)=' | sort || true; }

      want=$(systemctl --user show-environment | displays)
      if [ -z "$want" ]; then
        echo "no display in the user manager's environment; keeping the daemon"
        exit 0
      fi

      pid=$(systemctl --user show --property=MainPID --value tern-daemon.service)
      if [ "$pid" -eq 0 ]; then
        exec systemctl --user start tern-daemon.service
      fi
      if [ "$(tr '\0' '\n' <"/proc/$pid/environ" | displays)" = "$want" ]; then
        exit 0
      fi

      for shell in $(pgrep -P "$pid" || true); do
        if pgrep -P "$shell" >/dev/null; then
          echo "a pane is running a program; keeping the daemon without this session's display"
          exit 0
        fi
      done
      exec systemctl --user restart tern-daemon.service
    '';
  };
in
{
  # Tern reports TERM=xterm-kitty.
  home.packages = [
    tern
    pkgs.kitty.terminfo
  ];

  # Keeps panes' programs alive between windows, from boot (with lingering)
  # rather than login. Tern's own "Start at login" would write an autostart
  # entry naming the binary's store path, stale after the next update.
  systemd.user.services.tern-daemon = {
    Unit = {
      Description = "Tern session daemon";
      # Restarting kills every pane's program; the next boot picks up a new
      # build.
      X-RestartIfChanged = false;
    };
    Service = {
      ExecStart = "${lib.getExe tern} daemon";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };

  systemd.user.services.tern-daemon-adopt = {
    Unit = {
      Description = "Hand the Tern daemon this session's display";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe adopt;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # Serves this user's session daemon to other machines over QUIC (UDP 8376,
  # and iroh through iroh.stencil.so for clients that reach it by endpoint
  # id). Keys in ~/.ssh/authorized_keys log in as this user, and Tern's
  # pairing appends to that file, so it stays mutable state. Pairing would
  # otherwise write this unit itself, naming the binary's store path.
  systemd.user.services.tern-remote = {
    Unit = {
      Description = "Tern remote sessions (this user)";
      Documentation = "https://stencil.so";
      StartLimitIntervalSec = 60;
      StartLimitBurst = 10;
    };
    Service = {
      # Tern must be the main process: a stop signals it, and it closes its
      # sockets and exits.
      Type = "exec";
      ExecStart = "${lib.getExe tern} remote serve --user --state-dir ${config.xdg.configHome}/tern";
      Restart = "on-failure";
      RestartSec = 2;
      # Bad arguments (exit status 2) don't fix themselves by restarting.
      RestartPreventExitStatus = 2;
      # A session daemon it starts, and so every pane's program, outlives a
      # stop or restart of this service.
      KillMode = "process";
      TimeoutStopSec = 10;
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Read-only: Settings pages can't persist changes. Tern can't update itself
  # from the store, so its update checks only nag.
  xdg.configFile."tern/settings.json".text = builtins.toJSON (
    {
      auto_update = false;
    }
    // lib.optionalAttrs config.stylix.enable {
      font_family = fonts.monospace.name;
      # Tern sizes in whole px (a float fails the whole file), stylix in pt.
      font_size = builtins.floor (fonts.sizes.terminal * 4.0 / 3 + 0.5);
    }
  );

  # omp comes from mise, so Tern shouldn't offer to install or manage its own.
  # No setting controls the offer: Tern asks once and records the answer in
  # this state file, which it keeps writing, so it's only seeded when missing.
  home.activation.ternDeclineOmp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    state=${lib.escapeShellArg "${config.xdg.dataHome}/tern/omp/state.json"}
    if [ ! -e "$state" ]; then
      run mkdir -p "$(dirname "$state")"
      run cp ${
        pkgs.writeText "tern-omp-state.json" (
          builtins.toJSON {
            managed = false;
            checked = 0;
            no_build = false;
            offered = true;
          }
        )
      } "$state"
      run chmod 644 "$state"
    fi
  '';
}
