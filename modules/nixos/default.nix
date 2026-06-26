# Custom NixOS modules.
{
  desktop = ./desktop.nix;
  plasma6 = ./plasma6.nix;
  stylix-theme = ./stylix-theme.nix;
  pipewire = ./pipewire.nix;
  docker = ./docker.nix;
  bluetooth = ./bluetooth.nix;
  systemd-initrd = ./systemd-initrd.nix;
  dconf = ./dconf.nix;
}
