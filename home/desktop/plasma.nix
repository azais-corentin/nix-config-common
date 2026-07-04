# plasma-manager scaffold. Active only when the host actually runs Plasma 6
# (integrated eval reads osConfig.host.desktop; standalone HM falls back to
# "plasma6", making the import site itself the opt-in).
#
# `overrideConfig = false` keeps the module non-destructive: it merges into the
# existing kdeglobals / kwinrc / appletsrc rather than rewriting them.
#
# The monitor layout (kwinoutputconfig.json) is consumer-supplied via the
# `plasma.kwinOutputConfig` option: KWin rewrites this file at runtime, so it is
# materialized as a writable copy rather than a read-only /nix/store symlink.
{
  lib,
  pkgs,
  config,
  osConfig ? { },
  ...
}:
{
  options.plasma.kwinOutputConfig = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = "Rendered kwinoutputconfig.json to materialize into ~/.config.";
  };

  config = lib.mkIf ((osConfig.host.desktop or "plasma6") == "plasma6") (
    lib.mkMerge [
      {
        programs.plasma.enable = true;
        programs.plasma.overrideConfig = false;

        # Disable Baloo, the KDE file indexer/search.
        programs.plasma.configFile."baloofilerc"."Basic Settings"."Indexing-Enabled" = false;

        # KDE "Data and Storage Sizes": 0 = IEC (KiB/MiB/GiB). Written explicitly
        # so the result is IEC even if a stale non-default value already exists.
        programs.plasma.configFile."kdeglobals"."Locale"."BinaryUnitDialect" = 0;

        # KDE/Plasma natively themes Qt; stylix's home qt target is redundant and
        # only supports the qtct platform, so disable it on Plasma.
        stylix.targets.qt.enable = false;

        # Pin the Plasma color scheme to the stylix-generated one. plasma-manager's
        # apply_themes startup script runs `plasma-apply-colorscheme` at session
        # start, writing General.ColorScheme into ~/.config/kdeglobals — the top of
        # the KConfig cascade. Needed because `plasma-apply-lookandfeel --apply
        # stylix` does not refresh stale kdedefaults when LookAndFeelPackage is
        # already "stylix". Slug mirrors stylix modules/kde/hm.nix colorschemeSlug
        # (alphabetic chars of the scheme name; "untitled" for the unnamed shared
        # palette). Requires the stylix HM module to be imported by the consumer
        # (true for both nix-config and nix-config-work).
        programs.plasma.workspace.colorScheme = lib.mkIf config.stylix.enable (
          lib.concatStrings (
            lib.filter lib.isString (builtins.split "[^a-zA-Z]" config.lib.stylix.colors.scheme)
          )
        );

        programs.plasma.hotkeys.commands."launch-ghostty" = {
          name = "Launch Ghostty";
          comment = "Open the Ghostty terminal";
          key = "Meta+Return";
          command = "ghostty";
        };

        programs.plasma.hotkeys.commands."launch-firefox" = {
          name = "Launch Firefox";
          comment = "Open Firefox";
          key = "Meta+Z";
          command = "firefox";
        };

        programs.plasma.hotkeys.commands."launch-work-firefox" = {
          name = "Launch Work Firefox";
          comment = "Open Work Firefox";
          key = "Meta+Shift+Z";
          command = "firefox -P work";
        };

        programs.plasma.hotkeys.commands."launch-vscode" = {
          name = "Launch VS Code";
          comment = "Open Visual Studio Code";
          key = "Meta+C";
          command = "code";
        };

        programs.plasma.hotkeys.commands."launch-spotify" = {
          name = "Launch Spotify";
          comment = "Open Spotify";
          key = "Meta+S";
          command = "spotify";
        };

        # Open each launcher target maximized on first show. `apply = "initially"`
        # (the plasma-manager default) lets the user unmaximize later.
        programs.plasma.window-rules = [
          {
            description = "Ghostty: start maximized";
            match.window-class = {
              value = "ghostty";
              type = "substring";
            };
            apply = {
              maximizehoriz = true;
              maximizevert = true;
            };
          }
          {
            description = "VS Code: start maximized";
            match.window-class = {
              value = "Code";
              type = "substring";
            };
            apply = {
              maximizehoriz = true;
              maximizevert = true;
            };
          }
          {
            description = "Spotify: start maximized";
            match.window-class = {
              value = "spotify";
              type = "substring";
            };
            apply = {
              maximizehoriz = true;
              maximizevert = true;
            };
          }
        ];

        programs.plasma.shortcuts.kwin."Window Close" = "Meta+Q";
        programs.plasma.shortcuts.plasmashell."manage activities" = [ ];

        # Keep the numpad in digit mode from session start.
        programs.plasma.input.keyboard = {
          numlockOnStartup = "on";
          repeatDelay = 500;
          repeatRate = 50;
        };

        programs.plasma.kwin = {
          virtualDesktops = {
            rows = 1;
            names = [
              "Default"
              "Nix"
              "Desktop 3"
              "Desktop 4"
            ];
          };

          effects.shakeCursor.enable = true;

          effects.desktopSwitching = {
            animation = "slide";
            navigationWrapping = true;
          };
        };

        # Disable the top-left hot corner (default: Overview). KWin's overview
        # effect defaults BorderActivate to ElectricTopLeft (7); 9 = ElectricNone,
        # which is what the Screen Edges KCM writes when the corner is cleared.
        programs.plasma.configFile."kwinrc"."Effect-overview"."BorderActivate" = 9;

        # Don't ask for confirmation when deleting files (KIO-wide: Dolphin, file
        # dialogs). Captured from live kiorc on the desktop host.
        programs.plasma.configFile."kiorc"."Confirmations"."ConfirmDelete" = false;

        # Display and brightness (PowerDevil, AC/desktop profile). Written as raw
        # powerdevilrc keys rather than programs.plasma.powerdevil.AC.* because
        # plasma-manager asserts turnOffDisplay.idleTimeoutWhenLocked must be unset
        # when idleTimeout = "never" — and we want exactly "never + locked 1 min".
        # Sentinels match plasma-manager's own createPowerDevilConfig: -1 = "never".
        programs.plasma.configFile."powerdevilrc"."AC/Display" = {
          DimDisplayWhenIdle = false; # Dim automatically: Never
          DimDisplayIdleTimeoutSec = -1; # paired sentinel for dim disabled
          TurnOffDisplayIdleTimeoutSec = -1; # Turn off screen: Never
          TurnOffDisplayIdleTimeoutWhenLockedSec = 60; # When locked: 1 minute
        };

        # AZERTY top-row digits (unshifted): & é " '
        programs.plasma.shortcuts.kwin."Switch to Desktop 1" = "Meta+&";
        programs.plasma.shortcuts.kwin."Switch to Desktop 2" = "Meta+é";
        programs.plasma.shortcuts.kwin."Switch to Desktop 3" = "Meta+\"";
        programs.plasma.shortcuts.kwin."Switch to Desktop 4" = "Meta+'";

        # Move the active window to a virtual desktop. AZERTY top-row digits with Alt.
        programs.plasma.shortcuts.kwin."Window to Desktop 1" = "Meta+Alt+&";
        programs.plasma.shortcuts.kwin."Window to Desktop 2" = "Meta+Alt+é";
        programs.plasma.shortcuts.kwin."Window to Desktop 3" = "Meta+Alt+\"";
        programs.plasma.shortcuts.kwin."Window to Desktop 4" = "Meta+Alt+'";

        # Claude usage plasmoid; installed on every Plasma host and pinned into the
        # shared panel below. Source vendored at ./claude-usage-widget.
        home.packages = [ (pkgs.callPackage ./claude-usage-widget { }) ];

        # Regional formats (French) with an English UI. Hardcoded fr_FR (matches both
        # hosts) so the shared config is self-contained — no osConfig dependency.
        programs.plasma.configFile."plasma-localerc"."Formats" = {
          LC_NUMERIC = "fr_FR.UTF-8";
          LC_TIME = "fr_FR.UTF-8";
          LC_MONETARY = "fr_FR.UTF-8";
          LC_MEASUREMENT = "fr_FR.UTF-8";
          LC_PAPER = "fr_FR.UTF-8";
        };

        # Declarative panel: bottom, floating, 46px. plasma-manager applies this via a
        # desktop script that DELETES plasma-org.kde.plasma.desktop-appletsrc and
        # recreates containments — it re-runs only when this declaration changes.
        programs.plasma.panels = [
          {
            location = "bottom";
            floating = true;
            height = 46;
            widgets = [
              "org.kde.plasma.kickoff"
              "org.kde.plasma.icontasks"
              "org.nelieru.claudeusage"
              "org.kde.plasma.marginsseparator"
              "org.kde.plasma.systemtray"
              "org.kde.plasma.digitalclock"
              "org.kde.plasma.showdesktop"
            ];
          }
        ];
      }

      # Materialize the monitor layout as a writable copy (KWin rewrites it at
      # runtime; a read-only symlink into /nix/store would silently fail).
      (lib.mkIf (config.plasma.kwinOutputConfig != null) {
        home.activation.kwinoutputconfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          run install -Dm644 ${config.plasma.kwinOutputConfig} \
            "$HOME/.config/kwinoutputconfig.json"
        '';
      })
    ]
  );
}
