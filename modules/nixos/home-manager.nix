# Home Manager NixOS-module settings shared by every consumer. Import it next
# to the Home Manager NixOS module, which declares these options.
{
  # With home-manager.backupFileExtension set, a backup left by an earlier
  # switch otherwise aborts activation. Apps that save over their managed
  # config (Tern's settings.json) do so on every switch, so the newest backup
  # replaces the previous one instead.
  home-manager.overwriteBackup = true;
}
