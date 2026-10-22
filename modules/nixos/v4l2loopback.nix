# v4l2loopback: a virtual V4L2 capture node that any producer can write into,
# so sources that are not webcams (a phone over scrcpy, an OBS output) show up
# in browsers and videoconferencing apps as an ordinary camera.
#
#   scrcpy --video-source=camera --camera-facing=back \
#          --v4l2-sink=/dev/video42 --no-audio --no-window
#
# exclusive_caps=1 keeps the node advertising CAPTURE only while no producer is
# attached; Chromium, Firefox and OBS all skip devices that also claim OUTPUT.
# video_nr is pinned high so the path is stable across boots and does not race
# real capture hardware for /dev/video0.
{ config, lib, ... }:
{
  # TODO: drop once nixos-unstable carries NixOS/nixpkgs@40df9d166b. Since
  # kernel.dev ships System.map, the kernel's modules_install runs depmod into
  # $out, and its modules.* indexes collide with the kernel's in
  # aggregateModules (NixOS/nixpkgs#576406). Backports the upstream fix.
  boot.extraModulePackages = [
    (config.boot.kernelPackages.v4l2loopback.overrideAttrs (
      old:
      lib.optionalAttrs (old ? preBuild) {
        preBuild = "";
        installFlags = [
          "DEPMOD=true"
          "INSTALL_MOD_PATH=${placeholder "out"}"
        ];
      }
    ))
  ];
  boot.kernelModules = [ "v4l2loopback" ];
  boot.extraModprobeConfig = ''
    options v4l2loopback video_nr=42 card_label="Virtual Camera" exclusive_caps=1
  '';
}
