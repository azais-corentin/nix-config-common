# KDE Plasma 6 + plasma-login-manager (PLM, SDDM's successor on unstable).
# Gated on `host.desktop = "plasma6"` (declared in ./desktop.nix).
#
# `environment.plasma6.excludePackages` drops the listed apps from
# systemPackages, but the Plasma 6 NixOS module *also* wires
# `plasma-browser-integration` into Firefox and Chromium unconditionally;
# `mkForce`-ing both browser hooks here is what actually severs the
# integration end-to-end.
#
# The greeter monitor layout is consumer-supplied via
# `host.plasma6.kwinOutputConfig`; when null, PLM picks its own ordering.
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.host.plasma6.kwinOutputConfig = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    default = null;
    description = "Rendered kwinoutputconfig.json to seed the plasma-login-manager greeter monitor layout.";
  };

  config = lib.mkIf (config.host.desktop == "plasma6") (
    lib.mkMerge [
      {
        services.desktopManager.plasma6.enable = true;
        services.displayManager.plasma-login-manager.enable = true;

        environment.plasma6.excludePackages = with pkgs.kdePackages; [
          plasma-browser-integration
          elisa
          konsole
        ];

        programs.firefox.nativeMessagingHosts.packages = lib.mkForce [ ];
        programs.chromium.enablePlasmaBrowserIntegration = lib.mkForce false;

        # Seed NumLock=on for the plasma-login-manager greeter. PLM is a KWin-based
        # Wayland greeter, so the legacy SDDM `Numlock=on` knob is ignored; KWin
        # reads kcminputrc under the `plasmalogin` user instead (NumLock=0 means
        # "on at startup", 1 = off, 2 = leave as-is).
        systemd.services.plasmalogin-numlock = {
          description = "Seed NumLock=on for the plasma-login-manager greeter";
          wantedBy = [ "plasmalogin.service" ];
          before = [ "plasmalogin.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
          };
          script = ''
            ${pkgs.coreutils}/bin/install -d -m 0755 -o plasmalogin -g plasmalogin \
              /var/lib/plasmalogin/.config/kdedefaults
            ${pkgs.coreutils}/bin/install -m 0644 -o plasmalogin -g plasmalogin \
              ${pkgs.writeText "kcminputrc" ''
                [Keyboard]
                NumLock=0
              ''} \
              /var/lib/plasmalogin/.config/kdedefaults/kcminputrc
          '';
        };
      }

      # Seed the greeter's monitor layout so the login screen renders on the right
      # physical head. A oneshot ordered Before=plasmalogin refreshes the layout on
      # every activation (tmpfiles `C` would only seed missing/empty files).
      (lib.mkIf (config.host.plasma6.kwinOutputConfig != null) {
        systemd.services.plasmalogin-monitor-layout = {
          description = "Seed monitor layout for the plasma-login-manager greeter";
          wantedBy = [ "plasmalogin.service" ];
          before = [ "plasmalogin.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = false;
          };
          script = ''
            ${pkgs.coreutils}/bin/install -d -m 0755 -o plasmalogin -g plasmalogin \
              /var/lib/plasmalogin/.config
            ${pkgs.coreutils}/bin/install -m 0644 -o plasmalogin -g plasmalogin \
              ${config.host.plasma6.kwinOutputConfig} \
              /var/lib/plasmalogin/.config/kwinoutputconfig.json
          '';
        };
      })
    ]
  );
}
