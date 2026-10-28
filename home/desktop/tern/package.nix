# Tern, Stencil's multiplexing terminal. Its Linux archive is a single binary
# behind a build.stencil.so sign-in, so requireFile pins it and
# `mise run tern:fetch` adds it to each machine's store. The binary dlopens its
# windowing, GPU, audio, screen-capture and WebKit libraries, so they belong in
# the RPATH; its desktop entries are rebuilt here and its icons carved out of
# the binary.
{
  lib,
  stdenv,
  requireFile,
  autoPatchelfHook,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  python3,
  glib,
  glib-networking,
  kdePackages,
  libGL,
  libpulseaudio,
  libsecret,
  libxcb,
  libxkbcommon,
  linux-pam,
  pipewire,
  vulkan-loader,
  wayland,
  webkitgtk_4_1,
}:
let
  source = lib.importJSON ./source.json;
  desktopItem =
    args:
    makeDesktopItem (
      {
        desktopName = "Tern";
        icon = "so.stencil.tern";
        startupWMClass = "so.stencil.tern";
        terminal = false;
      }
      // args
    );
in
stdenv.mkDerivation {
  pname = "tern";
  inherit (source) version;

  src = requireFile {
    name = baseNameOf source.url;
    inherit (source) url hash;
    message = ''
      Tern's archive needs a build.stencil.so sign-in. Sign in there in Firefox,
      then run `mise run tern:fetch` in this repository to add
      ${baseNameOf source.url} to the Nix store.
    '';
  };

  sourceRoot = "tern";

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
    python3
  ];

  # NEEDED: libstdc++, libgcc_s and glibc only.
  buildInputs = [ (lib.getLib stdenv.cc.cc) ];

  runtimeDependencies = [
    libGL # libEGL, libGLESv2
    libpulseaudio # libpulse-simple
    libxcb
    libxkbcommon
    linux-pam
    pipewire # libpipewire-0.3, screen sharing
    vulkan-loader
    wayland # libwayland-client, libwayland-egl
    webkitgtk_4_1 # browser blocks
  ];

  # Patching a stripped Rust binary after another strip pass corrupts it.
  dontStrip = true;
  dontConfigure = true;
  dontBuild = true;

  desktopItems = [
    (desktopItem {
      name = "so.stencil.tern";
      exec = "tern";
      categories = [
        "System"
        "TerminalEmulator"
      ];
      extraConfig."X-TerminalArgExec" = "-e";
    })
    (desktopItem {
      name = "so.stencil.tern.open";
      exec = "tern --open-file %f";
      noDisplay = true;
      mimeTypes = [
        "text/plain"
        "text/markdown"
        "text/x-source"
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/svg+xml"
        "application/vnd.sqlite3"
        "application/x-sqlite3"
        "application/x-sqbpro"
        "application/x-ipynb+json"
        "inode/directory"
      ];
    })
    (desktopItem {
      name = "so.stencil.tern.url";
      exec = "tern --open-url %u";
      noDisplay = true;
      mimeTypes = [ "x-scheme-handler/tern" ];
    })
  ];

  # WebKitGTK needs glib-networking for TLS. Tern shells out to secret-tool for
  # the Stencil sign-in, gdbus for the portal's colour scheme and kdialog for
  # dialogs. The wrapper's environment reaches every pane, so PATH is
  # suffixed rather than prefixed.
  installPhase = ''
    runHook preInstall
    install -Dm755 tern $out/libexec/tern/tern
    makeWrapper $out/libexec/tern/tern $out/bin/tern \
      --prefix GIO_EXTRA_MODULES : ${glib-networking}/lib/gio/modules \
      --suffix PATH : ${
        lib.makeBinPath [
          glib
          kdePackages.kdialog
          libsecret
        ]
      }
    python3 ${./extract-icons.py} tern $out/share/icons/hicolor
    runHook postInstall
  '';

  meta = {
    description = "Multiplexing terminal with agent, browser and file blocks";
    homepage = "https://build.stencil.so/tern";
    license = lib.licenses.unfree;
    mainProgram = "tern";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
