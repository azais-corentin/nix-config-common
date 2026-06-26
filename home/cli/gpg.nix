# gpg + gpg-agent doubling as ssh-agent, using a Qt pinentry (KDE-native).
{ pkgs, ... }:
{
  programs.gpg.enable = true;
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-qt;
  };
}
