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

        # nixpkgs' graphical-desktop.nix writes 00-keyboard.conf with
        # `Option "XkbVariant" ""`; systemd >= 258 localed rejects empty
        # option values (string_is_safe) and discards the whole X11 context,
        # so `localectl` reports X11 Layout (unset). The PLM greeter's
        # `kwin_wayland --locale1` takes its keymap exclusively from locale1
        # (XKB_DEFAULT_LAYOUT), so the greeter fell back to QWERTY. Re-emit
        # the file with empty options omitted.
        environment.etc."X11/xorg.conf.d/00-keyboard.conf".text =
          let
            xkb = config.services.xserver.xkb;
            opt = name: value: lib.optionalString (value != "") "  Option \"${name}\" \"${value}\"\n";
          in
          lib.mkForce (
            ''
              Section "InputClass"
                Identifier "Keyboard catchall"
                MatchIsKeyboard "on"
            ''
            + opt "XkbModel" xkb.model
            + opt "XkbLayout" xkb.layout
            + opt "XkbOptions" xkb.options
            + opt "XkbVariant" xkb.variant
            + ''
              EndSection
            ''
          );

        # Seed the NumLock default for the plasma-login-manager greeter. PLM is
        # a KWin-based Wayland greeter, so the legacy SDDM `Numlock=on` knob is
        # ignored; KWin reads kcminputrc under the `plasmalogin` user instead
        # (NumLock=0 means "on at startup", 1 = off, 2 = leave as-is). The
        # greeter keyboard layout comes from systemd-localed via the
        # 00-keyboard.conf override above, not from any per-user config.
        systemd.services.plasmalogin-input-defaults = {
          description = "Seed NumLock default for the plasma-login-manager greeter";
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
