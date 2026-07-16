{
  description = "Shared NixOS and home-manager modules for nix-config and nix-config-work";

  # nixpkgs exists only for the repo-local dev tooling (`formatter`,
  # `devShells`). The shared modules are plain files evaluated with each
  # consumer's own nixpkgs (passed via the module system), so this flake
  # intentionally locks no second nixpkgs into consumers (they declare
  # `inputs.nixpkgs.follows = "nixpkgs"`).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forEachSystem =
        f:
        nixpkgs.lib.genAttrs [
          "x86_64-linux"
          "aarch64-linux"
        ] (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Leaf home-manager modules, safe to `attrValues`-import wholesale.
      homeModules = import ./modules/home-manager;

      # Custom NixOS modules: { desktop, plasma6, stylix-theme }.
      nixosModules = import ./modules/nixos;

      # Nested attrset of opt-in home-manager feature paths.
      homeFeatures = import ./home;

      # Generalized KWin monitor-layout JSON builder.
      lib.kwinOutputConfig = import ./lib/kwin-output-config.nix;

      # Dev tooling: dprint drives formatting (.dprint.json), hk runs the git
      # hooks (hk.pkl), mise provides tasks and the remaining tools (.mise/).
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          nativeBuildInputs = [
            # Pinned-or-newer mise, same source as the shared home module.
            (import ./home/cli/mise/package.nix pkgs)
          ]
          ++ builtins.attrValues {
            inherit (pkgs)
              dprint
              nixfmt
              gitleaks
              ;
          };
        };
      });

      formatter = forEachSystem (pkgs: pkgs.nixfmt);
    };
}
