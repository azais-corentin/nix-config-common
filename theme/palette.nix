# Shared stylix palette + fonts, applied via lib.mkDefault so consumers (or
# stylix's own image-derived scheme) can override. Imported by both
# home/stylix-theme.nix and modules/nixos/stylix-theme.nix.
{ pkgs, lib }:
{
  polarity = lib.mkDefault "dark";
  base16Scheme = lib.mkDefault {
    base00 = "222222";
    base01 = "363537";
    base02 = "525053";
    base03 = "69676c";
    base04 = "8b888f";
    base05 = "f7f1ff";
    base06 = "fdfdfa";
    base07 = "ffffff";
    base08 = "fc618d";
    base09 = "fd9353";
    base0A = "fce566";
    base0B = "7bd88f";
    base0C = "5ad4e6";
    base0D = "5ad4e6";
    base0E = "948ae3";
    base0F = "fd9353";
  };
  fonts = {
    monospace = {
      package = lib.mkDefault pkgs.nerd-fonts.jetbrains-mono;
      name = lib.mkDefault "JetBrainsMono Nerd Font";
    };
    sansSerif = {
      package = lib.mkDefault pkgs.inter;
      name = lib.mkDefault "Inter";
    };
    serif = {
      package = lib.mkDefault pkgs.source-serif;
      name = lib.mkDefault "Source Serif 4";
    };
    sizes = {
      applications = lib.mkDefault 11;
      terminal = lib.mkDefault 12;
      desktop = lib.mkDefault 11;
      popups = lib.mkDefault 11;
    };
  };
}
