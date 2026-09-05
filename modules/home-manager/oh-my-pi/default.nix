# oh-my-pi (omp) declarative Home Manager module.
#
# Manages declarative non-secret configuration in the default agent directory
# and any declared named-profile agent directories.
#
# The default mcp.json remains owned by the shared programs.mcp module. This
# module manages only the independent MCP documents declared by named profiles.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.oh-my-pi;
  helpers = import ./lib.nix { inherit lib pkgs; };
  inherit (helpers)
    isValidProfileName
    jsonFormat
    mkDefaultRecursive
    mkOpt
    num
    pruneNulls
    ;
  t = lib.types;

  settingsComponent = import ./settings.nix { inherit lib pkgs; };
  modelsComponent = import ./models.nix { inherit lib pkgs; };
  filesComponent = import ./files.nix { inherit lib pkgs; };

  profileOptions = settingsComponent.options // modelsComponent.options // filesComponent.options;

  mcpSchemaUrl = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";

  # Typed mirror of packages/coding-agent/src/config/mcp-schema.json. Every
  # submodule keeps a freeform escape hatch so keys omp adds later still pass.
  mcpStringMap = t.attrsOf t.str;

  mcpAuthType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      type = lib.mkOption {
        type = t.enum [
          "oauth"
          "apikey"
        ];
        description = "Auth strategy understood by OMP (required).";
      };
      credentialId = mkOpt t.str "Stored OAuth credential id from agent auth storage.";
      tokenUrl = mkOpt t.str "Token endpoint persisted for refresh.";
      clientId = mkOpt t.str "OAuth client id persisted for refresh.";
      clientSecret = mkOpt t.str "OAuth client secret persisted for refresh.";
      resource = mkOpt t.str "MCP resource URI persisted for OAuth resource indicators.";
    };
  };

  mcpOauthType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      clientId = mkOpt t.str "Explicit OAuth client id.";
      clientSecret = mkOpt t.str "Explicit OAuth client secret.";
      scope = mkOpt t.str "Requested OAuth scope.";
      redirectUri = mkOpt t.str "OAuth redirect URI.";
      callbackPort = mkOpt t.port "Local OAuth callback port (1-65535).";
      callbackPath = mkOpt t.str "Local OAuth callback path.";
      prompt = mkOpt t.str "OAuth prompt parameter sent during authorization; omitted by default unless the scope contains offline_access, which sends \"consent\". Set to the empty string to always omit.";
    };
  };

  mcpServerType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      type = mkOpt (t.enum [
        "stdio"
        "http"
        "sse"
      ]) "Transport; defaults to stdio when omitted. sse is legacy, prefer http.";
      command = mkOpt t.str "Executable to spawn (stdio only; required for stdio).";
      args = mkOpt (t.listOf t.str) "Arguments passed to the stdio server process.";
      env = mkOpt mcpStringMap "Environment variables passed to the stdio process.";
      cwd = mkOpt t.str "Working directory used when spawning the stdio process.";
      url = mkOpt t.str "MCP endpoint URL (http/sse only; required for those transports).";
      headers = mkOpt mcpStringMap "HTTP headers sent with MCP requests (http/sse only).";
      enabled = mkOpt t.bool "Whether OMP should try to connect this server.";
      timeout = mkOpt num "MCP request timeout in milliseconds (0 disables client-side MCP timeouts).";
      requestIdFormat =
        mkOpt
          (t.enum [
            "string"
            "number"
          ])
          "Encoding for outgoing JSON-RPC request ids (default: number). OMP-specific; servers imported from another tool's config ignore it.";
      auth = mkOpt mcpAuthType "Persisted auth strategy for this server.";
      oauth = mkOpt mcpOauthType "Explicit OAuth client settings used during /mcp reauth or initial connect.";
    };
  };

  mcpType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      "$schema" = lib.mkOption {
        type = t.str;
        default = mcpSchemaUrl;
        description = "JSON schema used to validate this profile's MCP configuration.";
      };
      mcpServers = lib.mkOption {
        type = t.attrsOf mcpServerType;
        default = { };
        description = "MCP server definitions keyed by server name.";
      };
      disabledServers = mkOpt (t.listOf t.str) "Denylist hiding discovered servers by name; highest precedence.";
      enabledServers = mkOpt (t.listOf t.str) "Allowlist overriding a discovered server's enabled: false flag; the denylist still wins.";
    };
  };

  # The schema's transport exclusivity (oneOf plus not/required) is not
  # expressible as a Nix type, so enforce it on the option. `apply` rather than
  # `assertions` keeps the check live under the bare evalModules test harness.
  checkMcp =
    mcp:
    if mcp == null then
      null
    else
      let
        violation =
          srv:
          let
            transport = if srv.type == null then "stdio" else srv.type;
          in
          if transport == "stdio" then
            if srv.url != null then
              "stdio transport must not set 'url'"
            else if srv.command == null then
              "stdio transport requires 'command'"
            else
              null
          else if srv.command != null then
            "${transport} transport must not set 'command'"
          else if srv.url == null then
            "${transport} transport requires 'url'"
          else
            null;
        problems = lib.filter (x: x != null) (
          lib.mapAttrsToList (
            name: srv:
            let
              reason = violation srv;
            in
            if reason == null then null else "server \"${name}\": ${reason}"
          ) mcp.mcpServers
        );
      in
      if problems == [ ] then
        mcp
      else
        throw "Invalid oh-my-pi MCP configuration: ${lib.concatStringsSep "; " problems}";

  profileModule = {
    options = profileOptions // {
      mcp = lib.mkOption {
        type = t.nullOr mcpType;
        default = null;
        apply = checkMcp;
        description = "Independent MCP configuration for this named profile.";
      };
    };

    config = mkDefaultRecursive (builtins.intersectAttrs profileOptions cfg);
  };

  renderProfile =
    {
      agentDir,
      artifactPrefix,
      profileConfig,
      mcp ? null,
    }:
    {
      files = lib.mkMerge [
        (modelsComponent.mkFiles {
          inherit agentDir artifactPrefix;
          config = profileConfig;
        })
        (filesComponent.mkFiles {
          inherit agentDir artifactPrefix;
          config = profileConfig;
        })
        (lib.optionalAttrs (mcp != null) {
          # Keep explicitly empty mcpServers objects after pruning.
          "${agentDir}/mcp.json".source = jsonFormat.generate "${artifactPrefix}-mcp.json" (
            pruneNulls mcp // { mcpServers = lib.mapAttrs (_: pruneNulls) mcp.mcpServers; }
          );
        })
      ];
      activation = settingsComponent.mkActivation {
        inherit agentDir artifactPrefix;
        config = profileConfig;
      };
    };

  profileConfigurations = [
    {
      agentDir = ".omp/agent";
      artifactPrefix = "omp";
      profileConfig = cfg;
    }
  ]
  ++ lib.mapAttrsToList (name: profile: {
    agentDir = ".omp/profiles/${name}/agent";
    artifactPrefix = "omp-profile-${name}";
    profileConfig = profile;
    inherit (profile) mcp;
  }) cfg.profiles;
  renderedProfiles = map renderProfile profileConfigurations;
in
{
  options.oh-my-pi = profileOptions // {
    enable = lib.mkEnableOption "oh-my-pi declarative configuration";

    profiles = lib.mkOption {
      type = t.attrsOf (t.submodule profileModule);
      default = { };
      apply =
        profiles:
        let
          invalid = lib.findFirst (name: !(isValidProfileName name)) null (builtins.attrNames profiles);
        in
        if invalid == null then
          profiles
        else
          throw "Invalid oh-my-pi profile name \"${invalid}\": expected a canonical OMP name matching ^[a-z0-9][a-z0-9._-]{0,63}$; \"default\", trailing dots, and Windows device names are reserved.";
      description = ''
        Named OMP profiles. Each profile inherits the default declarations at
        low priority and may override individual values independently.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge (map (profile: profile.files) renderedProfiles);
    home.activation = lib.mkMerge (map (profile: profile.activation) renderedProfiles);
  };
}
