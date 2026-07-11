# oh-my-pi (omp) declarative Home Manager module.
#
# Manages every user-level config file omp reads from the default agent
# directory and any declared named-profile agent directories.
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
  inherit (helpers) isValidProfileName jsonFormat mkDefaultRecursive;
  t = lib.types;

  settingsComponent = import ./settings.nix { inherit lib pkgs; };
  modelsComponent = import ./models.nix { inherit lib pkgs; };
  filesComponent = import ./files.nix { inherit lib pkgs; };

  profileOptions = settingsComponent.options // modelsComponent.options // filesComponent.options;

  mcpSchemaUrl = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";
  mcpType = t.submodule {
    freeformType = jsonFormat.type;
    options."$schema" = lib.mkOption {
      type = t.str;
      default = mcpSchemaUrl;
      description = "JSON schema used to validate this profile's MCP configuration.";
    };
  };

  profileModule = {
    options = profileOptions // {
      mcp = lib.mkOption {
        type = t.nullOr mcpType;
        default = null;
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
    lib.mkMerge [
      (settingsComponent.mkFiles {
        inherit agentDir artifactPrefix;
        config = profileConfig;
      })
      (modelsComponent.mkFiles {
        inherit agentDir artifactPrefix;
        config = profileConfig;
      })
      (filesComponent.mkFiles {
        inherit agentDir artifactPrefix;
        config = profileConfig;
      })
      (lib.optionalAttrs (mcp != null) {
        "${agentDir}/mcp.json".source = jsonFormat.generate "${artifactPrefix}-mcp.json" mcp;
      })
    ];

  defaultFiles = renderProfile {
    agentDir = ".omp/agent";
    artifactPrefix = "omp";
    profileConfig = cfg;
  };

  namedProfileFiles = lib.mapAttrsToList (
    name: profile:
    renderProfile {
      agentDir = ".omp/profiles/${name}/agent";
      artifactPrefix = "omp-profile-${name}";
      profileConfig = profile;
      inherit (profile) mcp;
    }
  ) cfg.profiles;
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
    home.file = lib.mkMerge ([ defaultFiles ] ++ namedProfileFiles);
  };
}
