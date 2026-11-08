{ lib, stdenvNoCC }:
stdenvNoCC.mkDerivation {
  pname = "claude-usage-widget";
  version = "6.0.0";

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
    description = "Plasma 6 applet showing pooled usage forecasts of every AI provider tracked by claude-usage-estimator";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
