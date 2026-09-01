# fastpotify is not in nixpkgs. Upstream's flake exposes a package, but its
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
  version = "0.4.1";
  arch =
    {
      x86_64-linux = "x86_64-unknown-linux-gnu";
      aarch64-linux = "aarch64-unknown-linux-gnu";
    }
    .${stdenv.hostPlatform.system};
  hash =
    {
      x86_64-linux = "sha256-aAYqFndN795BmU0SoXhB+1Na0otLYh2HTwR9BBdt4XM=";
      aarch64-linux = "sha256-pECPQnQJMIZ5+yvEN+fKRvKcASntjOH8psxJym7BIGs=";
    }
    .${stdenv.hostPlatform.system};
in
stdenv.mkDerivation {
  pname = "fastpotify";
  inherit version;

  src = fetchurl {
    url = "https://github.com/crmne/fastpotify/releases/download/v${version}/fastpotify-v${version}-${arch}.tar.gz";
    inherit hash;
  };

  nativeBuildInputs = [ autoPatchelfHook ];

  # NEEDED: libasound, libpulse, libpulse-simple, libgcc_s.
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
    install -Dm755 fastpotify $out/bin/fastpotify
    install -Dm644 packaging/applications/fastpotify.desktop \
      $out/share/applications/fastpotify.desktop
    install -Dm644 packaging/icons/fastpotify.svg \
      $out/share/icons/hicolor/scalable/apps/fastpotify.svg
    runHook postInstall
  '';

  meta = {
    description = "Fast native Spotify client with local playback and Spotify Connect";
    homepage = "https://fastpotify.rocks";
    license = lib.licenses.mit;
    mainProgram = "fastpotify";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
