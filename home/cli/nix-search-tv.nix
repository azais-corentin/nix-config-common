{ pkgs, ... }:
{
  home.packages = [
    pkgs.nix-search-tv
    # Runs upstream's fzf wrapper from the source store path at runtime;
    # builtins.readFile of it was import-from-derivation.
    (pkgs.writeShellApplication {
      name = "ns";
      runtimeInputs = [
        pkgs.fzf
        pkgs.nix-search-tv
      ];
      text = ''exec ${pkgs.runtimeShell} ${pkgs.nix-search-tv.src}/nixpkgs.sh "$@"'';
    })
  ];
}
