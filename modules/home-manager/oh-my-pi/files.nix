# Remaining files in the selected profile's agent directory: keybindings.yml,
# ssh.json, markdown content trees (skills/commands/rules/agents/prompts/
# instructions), raw file trees (themes/tools/hooks), and the top-level
# AGENTS.md / SYSTEM.md / RULES.md.
#
# Default-profile mcp.json is deliberately absent — it is owned by the shared
# programs.mcp module. Named-profile MCP rendering is composed in default.nix.
{ lib, pkgs }:
let
  helpers = import ./lib.nix { inherit lib pkgs; };
  inherit (helpers)
    mkOpt
    subType
    pruneNulls
    yamlFormat
    jsonFormat
    skillType
    contentType
    mkSkillEntries
    mkFileEntries
    mkRawFileEntries
    ;
  t = lib.types;

  sshHostType = subType {
    host = lib.mkOption {
      type = t.str;
      description = "Hostname or IP to connect to (required).";
    };
    username = mkOpt t.str "Login user.";
    port = mkOpt t.int "SSH port.";
    keyPath = mkOpt t.str "Path to the private key.";
    description = mkOpt t.str "Human-readable description shown in the host list.";
    compat = mkOpt t.bool "Use the compatibility (non-PTY) execution path.";
  };
in
{
  options = {
    keybindings = lib.mkOption {
      type = t.attrsOf (t.either t.str (t.listOf t.str));
      default = { };
      description = "Keybindings written to the selected profile's keybindings.yml.";
    };

    ssh.hosts = lib.mkOption {
      type = t.attrsOf sshHostType;
      default = { };
      description = "SSH hosts written to the selected profile's ssh.json.";
    };

    skills = lib.mkOption {
      type = t.attrsOf skillType;
      default = { };
      description = ''
        Skills installed under the selected profile's agent directory.
        Each value is one of:
        - A path to a SKILL.md file (symlinked as skills/<name>/SKILL.md)
        - A path to a directory containing SKILL.md and assets (symlinked recursively)
        - An inline string (written as skills/<name>/SKILL.md)
        - A "github:owner/repo/subdir@ref" string (fetched and symlinked recursively)
        - An attrset { src; subdir; } for pre-fetched sources (symlinked recursively)
      '';
    };

    commands = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Slash commands installed under the selected profile's commands directory.";
    };

    rules = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Rules installed under the selected profile's rules directory.";
    };

    agents = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Custom agents installed under the selected profile's agents directory.";
    };

    prompts = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Prompt snippets installed under the selected profile's prompts directory.";
    };

    instructions = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Instruction files installed under the selected profile's instructions directory.";
    };

    themes = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Themes installed under the selected profile's themes directory.";
    };

    tools = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Custom tools installed under the selected profile's tools directory.";
    };

    hooks = {
      pre = lib.mkOption {
        type = t.attrsOf contentType;
        default = { };
        description = "Pre hooks installed under the selected profile's hooks/pre directory.";
      };
      post = lib.mkOption {
        type = t.attrsOf contentType;
        default = { };
        description = "Post hooks installed under the selected profile's hooks/post directory.";
      };
    };

    agentsMd = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global AGENTS.md written to the selected profile's agent directory.";
    };

    systemPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global system prompt written to the selected profile's agent directory.";
    };

    rulesMd = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global RULES.md written to the selected profile's agent directory.";
    };
  };

  mkFiles =
    {
      agentDir,
      artifactPrefix,
      config,
    }:
    let
      mkDocFile =
        target: value:
        lib.optionalAttrs (value != null) {
          ${target} = if lib.isPath value then { source = value; } else { text = value; };
        };
    in
    lib.mkMerge [
      (lib.optionalAttrs (config.keybindings != { }) {
        "${agentDir}/keybindings.yml".source =
          yamlFormat.generate "${artifactPrefix}-keybindings.yml" config.keybindings;
      })
      (lib.optionalAttrs (config.ssh.hosts != { }) {
        "${agentDir}/ssh.json".source = jsonFormat.generate "${artifactPrefix}-ssh.json" {
          hosts = pruneNulls config.ssh.hosts;
        };
      })
      (lib.optionalAttrs (config.skills != { }) (mkSkillEntries agentDir config.skills))
      (lib.optionalAttrs (config.commands != { }) (
        mkFileEntries agentDir "commands" ".md" config.commands
      ))
      (lib.optionalAttrs (config.rules != { }) (mkFileEntries agentDir "rules" ".md" config.rules))
      (lib.optionalAttrs (config.agents != { }) (mkFileEntries agentDir "agents" ".md" config.agents))
      (lib.optionalAttrs (config.prompts != { }) (mkFileEntries agentDir "prompts" ".md" config.prompts))
      (lib.optionalAttrs (config.instructions != { }) (
        mkFileEntries agentDir "instructions" ".md" config.instructions
      ))
      (lib.optionalAttrs (config.themes != { }) (mkRawFileEntries agentDir "themes" config.themes))
      (lib.optionalAttrs (config.tools != { }) (mkRawFileEntries agentDir "tools" config.tools))
      (lib.optionalAttrs (config.hooks.pre != { }) (
        mkRawFileEntries agentDir "hooks/pre" config.hooks.pre
      ))
      (lib.optionalAttrs (config.hooks.post != { }) (
        mkRawFileEntries agentDir "hooks/post" config.hooks.post
      ))
      (mkDocFile "${agentDir}/AGENTS.md" config.agentsMd)
      (mkDocFile "${agentDir}/SYSTEM.md" config.systemPrompt)
      (mkDocFile "${agentDir}/RULES.md" config.rulesMd)
    ];
}
