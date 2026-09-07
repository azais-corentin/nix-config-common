# Codex system-wide config defaults.
#
# /etc/codex/config.toml is codex's lowest-precedence layer (see
# codex-rs/config/src/loader/README.md): it sits below ~/.codex/config.toml, so
# a user key still wins, and codex never rewrites it — unlike
# $CODEX_HOME/config.toml, where codex persists project trust levels and TUI
# state. /etc/codex/managed_config.toml would win over everything including
# `codex -c`, but upstream is phasing that layer out in favour of
# requirements.toml, so it is deliberately not used here.
#
# features.context_management.experimental_mode requires codex >= 0.153.0;
# older versions ignore the unknown key (strict config validation is off by
# default).
{
  environment.etc."codex/config.toml".text = ''
    # Managed by nix-config-common (modules/nixos/codex.nix).
    # Codex system layer: lowest precedence, ~/.codex/config.toml overrides it
    # per key.
    [features]
    context_management.experimental_mode = true
  '';
}
