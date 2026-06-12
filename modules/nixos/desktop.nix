# Desktop selector + bits shared by every DE.
#
# `host.desktop` is the single mutual-exclusion switch: each
# host/optional/<de>.nix wraps its body in `lib.mkIf` against this value, so
# only one DE is ever active.
#
# Shared always-on bits live here:
#   - udisks2 (file-manager automount)
#   - xdg.portal framework (no extraPortals — each DE ships its own backend)
#   - xdg.mime (default-application database)
#   - Wayland-friendly session vars for Electron/Chromium and Firefox.
{ lib, ... }:
{
  options.host.desktop = lib.mkOption {
    type = lib.types.enum [
      "cosmic"
      "gnome"
      "plasma6"
    ];
    default = "plasma6";
    description = "Which desktop environment to enable on this host.";
  };

  config = {
    services.udisks2.enable = true;

    xdg.portal.enable = true;
    xdg.portal.config.common.default = "*";
    xdg.mime.enable = true;

    environment.sessionVariables = {
      NIXOS_OZONE_WL = "1"; # Electron / Chromium native Wayland
      MOZ_ENABLE_WAYLAND = "1"; # Firefox native Wayland
    };
  };
}
