# Shared stylix palette/fonts for home-manager. Does NOT set stylix.enable or
# stylix.image — consumers own those. Inert until stylix.enable is true, so it
# is safe to import into every home (servers included).
{ pkgs, lib, ... }:
{
  stylix = (import ../theme/palette.nix { inherit pkgs lib; }) // {
    # HM master's release constant leads pinned nixpkgs/stylix; benign lag.
    enableReleaseChecks = lib.mkDefault false;
  };
}
