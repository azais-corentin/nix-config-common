# scrcpy, plus the android-tools it shells out to for adb. Pair with
# nixosModules.v4l2loopback to use a phone as a webcam; on its own scrcpy still
# mirrors and controls the device over USB or TCP/IP.
{ pkgs, ... }:
{
  home.packages = builtins.attrValues {
    inherit (pkgs)
      scrcpy
      android-tools
      ;
  };
}
