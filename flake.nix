{
  description = "Shared NixOS and home-manager modules for nix-config and nix-config-work";

  # nixpkgs exists only for the `formatter` output. The shared modules are plain
  # files evaluated with each consumer's own nixpkgs (passed via the module
  # system), so this flake intentionally locks no second nixpkgs into consumers
  # (they declare `inputs.nixpkgs.follows = "nixpkgs"`).
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    {
      # Leaf home-manager modules, safe to `attrValues`-import wholesale.
      homeModules = import ./modules/home-manager;

      # Custom NixOS modules: { desktop, plasma6, stylix-theme }.
      nixosModules = import ./modules/nixos;

      # Nested attrset of opt-in home-manager feature paths.
      homeFeatures = import ./home;

      # Generalized KWin monitor-layout JSON builder.
      lib.kwinOutputConfig = import ./lib/kwin-output-config.nix;

      formatter = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
      ] (s: nixpkgs.legacyPackages.${s}.nixfmt);
    };
}
