# PipeWire + WirePlumber, replacing PulseAudio. JACK apps: run via `pw-jack`
# (from `pipewire.jack`); the global `jack.enable` shim is deprecated.
{
  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
}
