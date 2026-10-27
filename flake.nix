{
  description = "Shared NixOS and home-manager modules for nix-config and nix-config-work";

  # nixpkgs exists only for the repo-local dev tooling and tests (`formatter`,
  # `devShells`, `checks`). The shared modules are plain files evaluated with each
  # consumer's own nixpkgs (passed via the module system), so this flake
  # intentionally locks no second nixpkgs into consumers (they declare
  # `inputs.nixpkgs.follows = "nixpkgs"`).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  # Ghostty's main branch for homeFeatures.desktop.ghostty, built locally
  # against the consumer's nixpkgs through the follows chain. Bump it here
  # (`nix flake update ghostty`), then bump nix-config-common in consumers.
  inputs.ghostty = {
    url = "github:ghostty-org/ghostty";
    inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    { nixpkgs, ghostty, ... }:
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

      # Custom NixOS modules (see modules/nixos/default.nix).
      nixosModules = import ./modules/nixos;

      # Nested attrset of opt-in home-manager features: paths, except
      # desktop.ghostty, which closes over the ghostty input.
      homeFeatures = import ./home { inherit ghostty; };

      # Generalized KWin monitor-layout JSON builder.
      lib.kwinOutputConfig = import ./lib/kwin-output-config.nix;

      # Dev shell shared with consumers ({ pkgs, packages ? [ ], inPlace ? false, ... }):
      # pinned mise, dprint, nixfmt, gitleaks, and a `.tooling` link to tooling/.
      lib.mkDevShell = import ./tooling/shell.nix;

      # This repo edits ./tooling in place; only its npm dependencies are linked.
      devShells = forEachSystem (pkgs: {
        default = import ./tooling/shell.nix {
          inherit pkgs;
          inPlace = true;
          packages = [ pkgs.nodejs ]; # npm install --package-lock-only for tooling/package-lock.json
        };
      });

      formatter = forEachSystem (pkgs: pkgs.nixfmt);

      # Module tests: bare lib.evalModules harness plus a runCommand that
      # executes the rendered activation scripts.
      checks = forEachSystem (pkgs: {
        oh-my-pi = import ./modules/home-manager/oh-my-pi/tests.nix { inherit pkgs; };
      });
    };
}
