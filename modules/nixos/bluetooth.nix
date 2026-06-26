# Bluetooth: powered on at boot, GATT claimed-services exported. No blueman —
# DEs ship their own tray; trayless WMs add services.blueman.enable locally.
{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    settings.GATT.ExportClaimedServices = "read-write";
  };
}
