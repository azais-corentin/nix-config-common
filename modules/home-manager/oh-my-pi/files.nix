# Remaining ~/.omp/agent/ files: keybindings.yml, ssh.json, the markdown content
# trees (skills/commands/rules/agents/prompts/instructions), the raw file trees
# (themes/tools/hooks), and the top-level AGENTS.md / SYSTEM.md / RULES.md.
#
# mcp.json is deliberately absent — it is owned by the shared programs.mcp module.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.oh-my-pi;
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

  # nullable AGENTS.md / SYSTEM.md / RULES.md entry → home.file value.
  mkDocFile =
    target: value:
    lib.optionalAttrs (value != null) {
      ${target} = if lib.isPath value then { source = value; } else { text = value; };
    };
in
{
  options.oh-my-pi = {
    keybindings = lib.mkOption {
      type = t.attrsOf (t.either t.str (t.listOf t.str));
      default = { };
      description = "Keybindings written to ~/.omp/agent/keybindings.yml (actionId → chord or chords).";
    };

    ssh.hosts = lib.mkOption {
      type = t.attrsOf sshHostType;
      default = { };
      description = "SSH hosts written to ~/.omp/agent/ssh.json (keyed by host name).";
    };

    skills = lib.mkOption {
      type = t.attrsOf skillType;
      default = { };
      description = ''
        Skills installed to ~/.omp/agent/skills/<name>/.
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
      description = "Slash commands installed to ~/.omp/agent/commands/<name>.md.";
    };

    rules = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Rules installed to ~/.omp/agent/rules/<name>.md.";
    };

    agents = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Custom agents installed to ~/.omp/agent/agents/<name>.md.";
    };

    prompts = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Prompt snippets installed to ~/.omp/agent/prompts/<name>.md.";
    };

    instructions = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Instruction files installed to ~/.omp/agent/instructions/<name>.md.";
    };

    themes = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Themes installed to ~/.omp/agent/themes/<name> (name includes the extension).";
    };

    tools = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Custom tools installed to ~/.omp/agent/tools/<name> (name includes the extension; directories symlinked recursively).";
    };

    hooks = {
      pre = lib.mkOption {
        type = t.attrsOf contentType;
        default = { };
        description = "Pre hooks installed to ~/.omp/agent/hooks/pre/<name> (name includes the extension).";
      };
      post = lib.mkOption {
        type = t.attrsOf contentType;
        default = { };
        description = "Post hooks installed to ~/.omp/agent/hooks/post/<name> (name includes the extension).";
      };
    };

    agentsMd = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global AGENTS.md written to ~/.omp/agent/AGENTS.md.";
    };

    systemPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global system prompt written to ~/.omp/agent/SYSTEM.md.";
    };

    rulesMd = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Global RULES.md written to ~/.omp/agent/RULES.md.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge [
      (lib.mkIf (cfg.keybindings != { }) {
        ".omp/agent/keybindings.yml".source = yamlFormat.generate "omp-keybindings.yml" cfg.keybindings;
      })
      (lib.mkIf (cfg.ssh.hosts != { }) {
        ".omp/agent/ssh.json".source = jsonFormat.generate "omp-ssh.json" {
          hosts = pruneNulls cfg.ssh.hosts;
        };
      })
      (lib.mkIf (cfg.skills != { }) (mkSkillEntries cfg.skills))
      (lib.mkIf (cfg.commands != { }) (mkFileEntries "commands" ".md" cfg.commands))
      (lib.mkIf (cfg.rules != { }) (mkFileEntries "rules" ".md" cfg.rules))
      (lib.mkIf (cfg.agents != { }) (mkFileEntries "agents" ".md" cfg.agents))
      (lib.mkIf (cfg.prompts != { }) (mkFileEntries "prompts" ".md" cfg.prompts))
      (lib.mkIf (cfg.instructions != { }) (mkFileEntries "instructions" ".md" cfg.instructions))
      (lib.mkIf (cfg.themes != { }) (mkRawFileEntries "themes" cfg.themes))
      (lib.mkIf (cfg.tools != { }) (mkRawFileEntries "tools" cfg.tools))
      (lib.mkIf (cfg.hooks.pre != { }) (mkRawFileEntries "hooks/pre" cfg.hooks.pre))
      (lib.mkIf (cfg.hooks.post != { }) (mkRawFileEntries "hooks/post" cfg.hooks.post))
      (mkDocFile ".omp/agent/AGENTS.md" cfg.agentsMd)
      (mkDocFile ".omp/agent/SYSTEM.md" cfg.systemPrompt)
      (mkDocFile ".omp/agent/RULES.md" cfg.rulesMd)
    ];
  };
}
