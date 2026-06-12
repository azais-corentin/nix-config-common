# Generalized KWin monitor-layout JSON builder.
#
# Consumers call this with their connected `outputs` (each attrset is merged
# over `commonDefaults`) and the `setups` positioning list. Returns the
# generated kwinoutputconfig.json derivation.
#
# `commonDefaults` carries the deliberate per-output overrides: ICC color
# source, PreferAccuracy power tradeoff, Full RGB range, sdrBrightness 230.
{
  pkgs,
  outputs,
  setups,
}:
let
  json = pkgs.formats.json { };

  commonDefaults = {
    allowDdcCi = true;
    allowSdrSoftwareBrightness = true;
    autoBrightnessCurve = [
      0
      0
      0
      0
      0
      0
    ];
    autoRotation = "InTabletMode";
    automaticBrightness = false;
    brightness = 1;
    colorPowerTradeoff = "PreferAccuracy";
    colorProfileSource = "ICC";
    customModes = [ ];
    detectedDdcCi = false;
    edrPolicy = "always";
    highDynamicRange = false;
    maxBitsPerColor = 0;
    overscan = 0;
    rgbRange = "Full";
    scale = 1;
    sdrBrightness = 230;
    sdrGamutWideness = 0;
    sharpness = 0;
    transform = "Normal";
    vrrPolicy = "Never";
    wideColorGamut = false;
  };

  payload = [
    {
      name = "outputs";
      data = map (o: commonDefaults // o) outputs;
    }
    {
      name = "setups";
      data = [
        {
          lidClosed = false;
          outputs = setups;
        }
      ];
    }
  ];
in
json.generate "kwinoutputconfig.json" payload
