# mise pinned to the official static (musl) release binary. nixpkgs trails
# upstream mise releases by days-to-weeks; this guarantees a floor version and
# retires itself: as soon as pkgs.mise reaches `version`, it is used instead
# (at which point this pin can be bumped or the file inlined away).
pkgs:
let
  version = "2026.7.7";
  target =
    {
      x86_64-linux = {
        arch = "x64";
        hash = "sha256-742hWxs4KaUfAWm5FnPbRRflIOX6zX0Q0xH/0S6/s1g=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-H+oyVtxSBs4KqpG4mSASHwoKWpBuTaWBMYa6bUdKAjk=";
      };
    }
    .${pkgs.stdenv.hostPlatform.system};
in
if pkgs.lib.versionAtLeast pkgs.mise.version version then
  pkgs.mise
else
  pkgs.stdenvNoCC.mkDerivation {
    pname = "mise";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/jdx/mise/releases/download/v${version}/mise-v${version}-linux-${target.arch}-musl.tar.gz";
      inherit (target) hash;
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
