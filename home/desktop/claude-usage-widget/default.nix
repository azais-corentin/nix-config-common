{ lib, stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "claude-usage-widget";
  version = "1.1.0";

  src = ./org.nelieru.claudeusage;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/plasma/plasmoids/org.nelieru.claudeusage"
    cp -r . "$out/share/plasma/plasmoids/org.nelieru.claudeusage/"
    runHook postInstall
  '';

  meta = {
    description = "Plasma 6 applet showing per-account Anthropic Claude subscription usage via oh-my-pi";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
