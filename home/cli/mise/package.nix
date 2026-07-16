# mise pinned to the official static (musl) release binary. nixpkgs trails
# upstream mise releases by days-to-weeks; this guarantees a floor version and
# retires itself: as soon as pkgs.mise reaches `version`, it is used instead
# (at which point this pin can be bumped or the file inlined away).
# Bump via `mise run bump:mise`.
pkgs:
let
  source = builtins.fromJSON (builtins.readFile ./source.json);
  inherit (source) version;
  system = pkgs.stdenv.hostPlatform.system;
  # nix system -> release asset arch
  arch =
    {
      x86_64-linux = "x64";
      aarch64-linux = "arm64";
    }
    .${system};
  hash = source.hashes.${system};
in
if pkgs.lib.versionAtLeast pkgs.mise.version version then
  pkgs.mise
else
  pkgs.stdenvNoCC.mkDerivation {
    pname = "mise";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-${arch}-musl.tar.gz";
      inherit hash;
    };

    # Tarball root: bin/ (static binary), share/ (fish vendor conf), man/.
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r bin share man $out/
      runHook postInstall
    '';

    meta = {
      description = "Dev tools, env vars, task runner (pinned release binary)";
      homepage = "https://mise.jdx.dev";
      license = pkgs.lib.licenses.mit;
      mainProgram = "mise";
    };
  }
