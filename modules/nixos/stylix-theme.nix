# Shared stylix palette/fonts for NixOS. Does NOT set stylix.enable or
# stylix.image — consumers own those. HM stylix values propagate from this
# NixOS module automatically (stylix.homeManagerIntegration), so consumers
# that enable that integration must NOT also import the HM stylix-theme.
{ pkgs, lib, ... }:
{
  stylix = import ../../theme/palette.nix { inherit pkgs lib; };
}
