# Dev shell shared by nix-config-common and its consumers: pinned mise, the
# formatters dprint drives, gitleaks, and the tooling bundle. Consumers get
# `.tooling` linked to the bundle locked by their flake.lock, so hk.pkl,
# .dprint.json, and .mise/config.toml reference one stable relative path.
# This repo (inPlace) uses ./tooling directly and only links its npm deps.
{
  pkgs,
  packages ? [ ],
  inPlace ? false,
  ...
}@args:
let
  tooling = import ./. { inherit pkgs; };
  link =
    if inPlace then
      ''ln -sfnT ${tooling.nodeModules}/node_modules "$root/tooling/node_modules"''
    else
      ''ln -sfnT ${tooling} "$root/.tooling"'';
in
pkgs.mkShell (
  removeAttrs args [
    "pkgs"
    "packages"
    "inPlace"
  ]
  // {
    packages = [
      # Pinned-or-newer mise, same source as the shared home module.
      (import ../home/cli/mise/package.nix pkgs)
      pkgs.dprint
      pkgs.nixfmt
      pkgs.gitleaks
    ]
    ++ packages;
    shellHook = ''
      if root=$(git rev-parse --show-toplevel 2>/dev/null); then
        ${link}
      fi
    ''
    + args.shellHook or "";
  }
)
