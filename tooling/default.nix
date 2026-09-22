# Shared dev-tooling bundle: hk/dprint base configs, generic mise tasks, the
# updater library, and the npm packages the tasks import. The npm tree is
# built offline from package-lock.json (integrity-pinned), so the bundle is
# fully determined by the flake lock.
{ pkgs }:
let
  nodeModules = pkgs.importNpmLock.buildNodeModules {
    npmRoot = ./.;
    inherit (pkgs) nodejs;
    derivationArgs = {
      # Same as .npmrc, which the build doesn't see: the lockfile has no peers.
      npmFlags = [ "--legacy-peer-deps" ];
      # npmConfigHook exports npm_config_nodedir for node-gyp, which current npm
      # warns about as an unknown config. Nothing here compiles native addons.
      preConfigure = ''
        npm() { env -u npm_config_nodedir npm "$@"; }
      '';
    };
  };
in
pkgs.runCommand "nix-config-tooling" { passthru = { inherit nodeModules; }; } ''
  cp -r ${./.} $out
  chmod u+w $out
  ln -sfnT ${nodeModules}/node_modules $out/node_modules
''
