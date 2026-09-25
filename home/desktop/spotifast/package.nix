# Spotifast is not in nixpkgs. Upstream's flake exposes a package, but its
# cargoLock has no outputHashes for the librespot/projectm git patches, so it
# fails to evaluate; and a source build needs cmake + bindgen for libprojectM.
# The official release tarball carries the binary, desktop entry and icon.
{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  alsa-lib,
  libpulseaudio,
  libxkbcommon,
  wayland,
  libGL,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
}:
let
  version = "0.10.2";
  arch =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
    }
    .${stdenv.hostPlatform.system};
  hash =
    {
      x86_64-linux = "sha256-uVeXBXcE0BPeJ+FHhd4zYa03cn6jyJtNRDSatBH2XOM=";
      aarch64-linux = "sha256-bjIHyB3gQ8RJ6k9B7zqCrxdVSCVb9yEqxNJJPnzVou8=";
    }
    .${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "spotifast";
  inherit version;

  src = fetchurl {
    url = "https://github.com/crmne/spotifast/releases/download/v${version}/spotifast-v${version}-${arch}.tar.gz";
    inherit hash;
  };

  sourceRoot = "spotifast-v${version}-${arch}";

  nativeBuildInputs = [ autoPatchelfHook ];

  # NEEDED: libasound, libpulse, libpulse-simple, libstdc++, libgcc_s.
  buildInputs = [
    (lib.getLib stdenv.cc.cc)
    alsa-lib
    libpulseaudio
  ];

  # The egui/glutin GUI dlopens its windowing and GL libraries at run time, so
  # they belong in the RPATH rather than in buildInputs.
  runtimeDependencies = [
    libxkbcommon
    wayland
    libGL
    libx11
    libxcursor
    libxi
    libxrandr
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 spotifast $out/bin/spotifast
    install -Dm644 packaging/applications/spotifast.desktop \
      $out/share/applications/spotifast.desktop
    substituteInPlace $out/share/applications/spotifast.desktop \
      --replace-fail "Exec=spotifast" "Exec=$out/bin/spotifast"
    install -Dm644 packaging/icons/spotifast.svg \
      $out/share/icons/hicolor/scalable/apps/spotifast.svg
    runHook postInstall
  '';

  meta = {
    description = "Fast native Spotify client with local playback and Spotify Connect";
    homepage = "https://spotifast.rocks";
    license = lib.licenses.mit;
    mainProgram = "spotifast";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
