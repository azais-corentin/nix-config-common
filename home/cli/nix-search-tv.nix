{ pkgs, ... }:
{
  home.packages = with pkgs; [
    nix-search-tv
    (pkgs.writeShellApplication {
      name = "ns";
      runtimeInputs = with pkgs; [
        fzf
        nix-search-tv
      ];
      # Fix https://github.com/3timeslazy/nix-search-tv/issues/17
      excludeShellChecks = [ "SC2016" ];
      text = builtins.readFile "${pkgs.nix-search-tv.src}/nixpkgs.sh";
    })
  ];
}
