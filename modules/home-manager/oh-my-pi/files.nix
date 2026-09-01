# Declarative non-secret files in the selected profile's agent directory:
# keybindings.yml, ssh.json, lsp.json, dap.json, WATCHDOG.yml, markdown content
# trees, raw resource trees (including extensions), and top-level prompt
# documents (including PERSONALITY.md).
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
    num
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

  lspCapabilitiesType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      flycheck = mkOpt t.bool "Server supports Flycheck operations.";
      ssr = mkOpt t.bool "Server supports structural search and replace.";
      expandMacro = mkOpt t.bool "Server supports macro expansion.";
      runnables = mkOpt t.bool "Server supports runnable discovery.";
      relatedTests = mkOpt t.bool "Server supports related-test discovery.";
    };
  };

  lspServerType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      command = mkOpt t.str "Language-server executable.";
      args = mkOpt (t.listOf t.str) "Arguments passed to the language server.";
      fileTypes = mkOpt (t.listOf t.str) "File types handled by the language server.";
      languageId = mkOpt t.str "LSP language identifier sent in didOpen; inferred from the file path when omitted.";
      rootMarkers = mkOpt (t.listOf t.str) "Files or directories that identify a project root.";
      initOptions = mkOpt (t.attrsOf jsonFormat.type) "Initialization options sent to the language server.";
      settings = mkOpt (t.attrsOf jsonFormat.type) "Language-server workspace settings.";
      disabled = mkOpt t.bool "Disable this language server.";
      isLinter = mkOpt t.bool "Use this server only for diagnostics and code actions.";
      workspaceReadyTimings = mkOpt (t.submodule {
        freeformType = jsonFormat.type;
        options = {
          timeoutMs = mkOpt num "Overall workspace-ready timeout in milliseconds.";
          pollMs = mkOpt num "Interval between workspace-ready polls in milliseconds.";
          settleMs = mkOpt num "Quiet period the workspace must stay ready before it counts, in milliseconds.";
          statusRequestTimeoutMs = mkOpt num "Timeout for a single status request in milliseconds.";
        };
      }) "Per-server overrides for rust-analyzer workspace-ready polling.";
      warmupTimeoutMs = mkOpt num "Per-server warmup timeout in milliseconds.";
      capabilities = mkOpt lspCapabilitiesType "Language-server capability overrides.";
    };
  };

  dapAttachDefaultsType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      skipAttachRequest = mkOpt t.bool "The adapter is already attached, so omp sends no DAP attach request.";
    };
  };

  dapAdapterType = t.submodule {
    freeformType = jsonFormat.type;
    options = {
      command = lib.mkOption {
        type = t.str;
        description = "Debug adapter executable or path (required; omp drops an adapter whose command is missing or empty).";
      };
      args = mkOpt (t.listOf t.str) "Arguments passed to the adapter. With connectMode = \"tcp\", the literal \${port} placeholder in an argument is replaced by the chosen port.";
      languages = mkOpt (t.listOf t.str) "Languages this adapter handles.";
      fileTypes = mkOpt (t.listOf t.str) "File extensions this adapter handles; omp lower-cases them on load.";
      rootMarkers = mkOpt (t.listOf t.str) "Files or directories that mark a project root for this adapter.";
      launchDefaults = mkOpt (t.attrsOf jsonFormat.type) "DAP launch-request defaults, merged before program/cwd/args.";
      attachDefaults = mkOpt dapAttachDefaultsType "DAP attach-request defaults.";
      connectMode =
        mkOpt
          (t.enum [
            "stdio"
            "socket"
            "tcp"
          ])
          "Transport. stdio (the default) uses stdin/stdout pipes; socket is an adapter-specific socket launch (currently Delve); tcp spawns a DAP server with \${port} substituted in args and connects to it.";
      acceptsDirectoryProgram = mkOpt t.bool "Accept a directory as the launch program (for example dlv treating it as a Go package path).";
    };
  };

  advisorType = subType {
    name = lib.mkOption {
      type = t.str;
      description = "Advisor display name (required).";
    };
    model = mkOpt t.str "Model selector for this advisor.";
    tools = mkOpt (t.listOf t.str) "Tools granted to this advisor; an explicit empty list grants none.";
    instructions = mkOpt t.lines "Specialized instructions appended to the shared baseline.";
    enabled = mkOpt t.bool "Whether this advisor is active.";
  };

  watchdogType = subType {
    instructions = mkOpt t.lines "Shared instructions prepended to every advisor.";
    advisors = mkOpt (t.listOf advisorType) "Declared passive advisors.";
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

    extensions = lib.mkOption {
      type = t.attrsOf contentType;
      default = { };
      description = "Extension modules installed under the selected profile's extensions directory; names are used verbatim.";
    };

    lsp = lib.mkOption {
      type = t.submodule {
        freeformType = jsonFormat.type;
        options = {
          idleTimeoutMs = mkOpt num "Shut down idle LSP clients after this many milliseconds.";
          servers = lib.mkOption {
            type = t.attrsOf lspServerType;
            default = { };
            description = "Language-server definitions and partial built-in overrides.";
          };
        };
      };
      default = { };
      description = "Wrapped LSP configuration written to the selected profile's lsp.json.";
    };

    dap.adapters = lib.mkOption {
      type = t.attrsOf dapAdapterType;
      default = { };
      description = "Debug adapters written to the selected profile's dap.json, merged over omp's built-in adapters.";
    };

    watchdog = lib.mkOption {
      type = t.nullOr watchdogType;
      default = null;
      description = "Passive advisor configuration written to the selected profile's WATCHDOG.yml.";
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

    personalityPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Personality-block override written to PERSONALITY.md in the selected profile's agent directory. omp ignores it when settings.personality = \"none\", and falls back to the configured preset when the file is empty.";
    };

    appendSystemPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Additional system prompt written to APPEND_SYSTEM.md in the selected profile's agent directory.";
    };

    titleSystemPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Session-title system prompt written to TITLE_SYSTEM.md in the selected profile's agent directory.";
    };

    watchdogPrompt = lib.mkOption {
      type = t.nullOr contentType;
      default = null;
      description = "Shared advisor prompt written to WATCHDOG.md in the selected profile's agent directory.";
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
      lspConfig = pruneNulls config.lsp;
      watchdogConfig = if config.watchdog == null then { } else pruneNulls config.watchdog;
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
      (lib.optionalAttrs (lspConfig != { }) {
        "${agentDir}/lsp.json".source = jsonFormat.generate "${artifactPrefix}-lsp.json" lspConfig;
      })
      (lib.optionalAttrs (config.dap.adapters != { }) {
        "${agentDir}/dap.json".source = jsonFormat.generate "${artifactPrefix}-dap.json" {
          adapters = pruneNulls config.dap.adapters;
        };
      })
      (lib.optionalAttrs (watchdogConfig != { }) {
        "${agentDir}/WATCHDOG.yml".source =
          yamlFormat.generate "${artifactPrefix}-watchdog.yml" watchdogConfig;
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
      (lib.optionalAttrs (config.extensions != { }) (
        mkRawFileEntries agentDir "extensions" config.extensions
      ))
      (lib.optionalAttrs (config.hooks.pre != { }) (
        mkRawFileEntries agentDir "hooks/pre" config.hooks.pre
      ))
      (lib.optionalAttrs (config.hooks.post != { }) (
        mkRawFileEntries agentDir "hooks/post" config.hooks.post
      ))
      (mkDocFile "${agentDir}/AGENTS.md" config.agentsMd)
      (mkDocFile "${agentDir}/SYSTEM.md" config.systemPrompt)
      (mkDocFile "${agentDir}/PERSONALITY.md" config.personalityPrompt)
      (mkDocFile "${agentDir}/APPEND_SYSTEM.md" config.appendSystemPrompt)
      (mkDocFile "${agentDir}/TITLE_SYSTEM.md" config.titleSystemPrompt)
      (mkDocFile "${agentDir}/WATCHDOG.md" config.watchdogPrompt)
      (mkDocFile "${agentDir}/RULES.md" config.rulesMd)
    ];
}
