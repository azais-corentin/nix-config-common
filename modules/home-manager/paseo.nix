{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.paseo;
  validAddress =
    address:
    let
      octets = lib.splitString "." address;
      decimal = value: builtins.match "(0|[1-9][0-9]{0,2})" value != null;
      numbers = map lib.toInt octets;
    in
    builtins.length octets == 4
    && lib.all decimal octets
    && lib.all (value: value <= 255) numbers
    && builtins.elemAt numbers 0 == 100
    && builtins.elemAt numbers 1 >= 64
    && builtins.elemAt numbers 1 <= 127;

  profiles = [
    {
      name = "default";
      settings = config.oh-my-pi.settings;
    }
  ]
  ++ lib.mapAttrsToList (name: profile: {
    inherit name;
    inherit (profile) settings;
  }) config.oh-my-pi.profiles;
  modelFor =
    profile:
    let
      selector = profile.settings.modelRoles.default or null;
      suffix =
        if selector == null then
          null
        else
          builtins.match "(.*):(off|minimal|low|medium|high|xhigh|max)" selector;
    in
    if suffix == null then selector else builtins.head suffix;
  validModel =
    profile:
    let
      model = modelFor profile;
    in
    model == null || builtins.match "[a-zA-Z0-9_-]+/[a-zA-Z0-9_./:-]+" model != null;
  providerId =
    name:
    if name == "default" then
      "omp"
    else
      "omp-" + lib.replaceStrings [ "-" "." "_" ] [ "-h" "-d" "-u" ] name;
  providers =
    lib.genAttrs [ "claude" "codex" "copilot" "opencode" "pi" ] (_: {
      enabled = false;
    })
    // builtins.listToAttrs (
      map (profile: {
        name = providerId profile.name;
        value = {
          enabled = true;
          label = "OMP (${profile.name})";
          env.OMP_PROFILE = profile.name;
        }
        // (if profile.name == "default" then { command = [ "omp" ]; } else { extends = "omp"; })
        // lib.optionalAttrs (modelFor profile != null) {
          additionalModels = [
            {
              id = modelFor profile;
              label = modelFor profile;
              isDefault = true;
            }
          ];
        };
      }) profiles
    );
  declarations = (pkgs.formats.json { }).generate "paseo-providers.json" providers;
  listen = "${cfg.listenAddress}:${toString cfg.port}";
  jq = lib.getExe pkgs.jq;
  prepare = pkgs.writeShellScript "paseo-prepare-config" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath [ pkgs.coreutils ]}:"$PATH"
    umask 077
    directory="$HOME/.paseo"
    if [ ! -d "$directory" ]; then
      mkdir -m 700 -p -- "$directory"
    fi
    temporary=$(mktemp "$directory/.config.json.XXXXXX")
    trap 'rm -f -- "$temporary"' EXIT
    if [ -e "$directory/config.json" ]; then
      ${jq} -e -s '
        length == 1 and (.[0] | type == "object" and (.version == null or .version == 1))
      ' "$directory/config.json" >/dev/null
      source="$directory/config.json"
    else
      printf '{}\n' >"$temporary"
      source="$temporary"
    fi
    providers=$(${jq} -c . ${declarations})
    for profile in ${lib.escapeShellArgs (map (profile: profile.name) profiles)}; do
      suffix=""
      if [ "$profile" != default ]; then
        suffix="/profiles/$profile"
      fi
      sessions="$HOME/.omp$suffix/agent/sessions"
      if [ -n "''${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/omp$suffix" ]; then
        sessions="$XDG_DATA_HOME/omp$suffix/sessions"
      fi
      providers=$(printf '%s' "$providers" | ${jq} -c --arg profile "$profile" --arg sessions "$sessions" '
        with_entries(if .value.env.OMP_PROFILE == $profile then .value.params.sessionDir = $sessions else . end)
      ')
    done
    merged=$(${jq} --arg listen ${lib.escapeShellArg listen} --argjson providers "$providers" '
      ."$schema" = "https://paseo.sh/schemas/paseo.config.v1.json"
      | .version = 1
      | .daemon.listen = $listen
      | .daemon.relay.enabled = true
      | del(.daemon.auth.password)
      | .agents.providers = $providers
    ' "$source")
    printf '%s\n' "$merged" >"$temporary"
    chmod 600 "$temporary"
    if [ -e "$directory/config.json" ] && [ ! -e "$directory/config.pre-nix.json" ]; then
      backup=$(mktemp "$directory/.config.pre-nix.json.XXXXXX")
      trap 'rm -f -- "$temporary" "$backup"' EXIT
      install -m 600 -- "$directory/config.json" "$backup"
      # A hard link publishes the complete backup without replacing an existing one.
      ln -- "$backup" "$directory/config.pre-nix.json"
      rm -f -- "$backup"
    fi
    mv -fT -- "$temporary" "$directory/config.json"
  '';
  innerLauncher = pkgs.writeShellScript "paseo-launch" ''
    set -euo pipefail
    unset PASEO_PASSWORD OMP_PROFILE PI_PROFILE PI_CODING_AGENT_DIR OMP_AGENT_DIR OMP_SESSION_DIR
    if ! ${pkgs.iproute2}/bin/ip -j -4 address show | ${jq} -e --arg address ${lib.escapeShellArg cfg.listenAddress} \
      'any(.[].addr_info[]?; .local == $address)' >/dev/null; then
      echo "Paseo: configured Tailscale IPv4 address is not assigned." >&2
      exit 1
    fi
    ${prepare}
    exec paseo daemon start --foreground --home "$HOME/.paseo" \
      --listen ${lib.escapeShellArg listen} --relay
  '';
  launcher = pkgs.writeShellScript "paseo-service" ''
    set -eo pipefail
    . ${lib.escapeShellArg "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"}
    export PATH=${lib.escapeShellArg "${config.home.profileDirectory}/bin"}:"$HOME/.nix-profile/bin":${lib.escapeShellArg "/etc/profiles/per-user/${config.home.username}/bin"}:/run/current-system/sw/bin:"''${MISE_DATA_DIR:-''${XDG_DATA_HOME:-$HOME/.local/share}/mise}/shims":"''${PATH:-}"
    export MISE_EXEC_AUTO_INSTALL=false
    exec ${lib.getExe config.programs.mise.package} exec -- ${innerLauncher}
  '';
in
{
  options.services.paseo = {
    enable = lib.mkEnableOption "the OMP-only Paseo user service";
    listenAddress = lib.mkOption {
      type = lib.types.str;
      description = "Assigned Tailscale IPv4 address in 100.64.0.0/10.";
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 6767;
      description = "Paseo TCP port on the Tailscale interface.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "services.paseo requires Linux.";
      }
      {
        assertion = config.programs.mise.enable;
        message = "services.paseo requires programs.mise.enable.";
      }
      {
        assertion = config.oh-my-pi.enable;
        message = "services.paseo requires oh-my-pi.enable and the mise-installed OMP binary.";
      }
      {
        assertion = validAddress cfg.listenAddress;
        message = "services.paseo.listenAddress must be a Tailscale IPv4 address in 100.64.0.0/10.";
      }
    ]
    ++ map (profile: {
      assertion = validModel profile;
      message = "services.paseo: OMP profile ${profile.name} requires a direct provider/model default, without aliases or fallback chains.";
    }) profiles;

    systemd.user.services.paseo = {
      Unit = {
        Description = "Paseo OMP daemon on Tailscale";
        StartLimitIntervalSec = 0;
      };
      Service = {
        Type = "simple";
        ExecStart = toString launcher;
        WorkingDirectory = config.home.homeDirectory;
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
