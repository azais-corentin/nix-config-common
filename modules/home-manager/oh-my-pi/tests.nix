let
  flake = builtins.getFlake (toString ../../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;

  mcpSchemaUrl = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";

  homeFileModule = { lib, ... }: {
    options.home.file = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };

  miseGlobalConfigModule = { lib, ... }: {
    options.programs.mise.globalConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };

  evaluate =
    declaration:
    lib.evalModules {
      specialArgs = { inherit pkgs; };
      modules = [
        ./default.nix
        homeFileModule
        { oh-my-pi = declaration; }
      ];
    };

  sharedFeature = lib.evalModules {
    specialArgs = { inherit pkgs; };
    modules = [
      ./default.nix
      homeFileModule
      miseGlobalConfigModule
      ../../../home/cli/mise/oh-my-pi.nix
    ];
  };

  main = evaluate {
    enable = true;

    settings = {
      personality = "pragmatic";
      task.disabledAgents = [
        "scout"
        "oracle"
      ];
      todo.remindersMax = 5;
      dev.autoqaConsent = "granted";
      tools.xdev = false;
      task.prewalk = true;
      modelRoleStorage = "project";
      hindsight = {
        requestTimeoutMs = 31000;
        reflectTimeoutMs = 121000;
        recallTimeoutMs = 32000;
        retainTimeoutMs = 61000;
      };
      providers = {
        image = "openai-codex";
        kimiApiFormat = "auto";
      };
    };

    models.providers.local = {
      baseUrl = "http://default.invalid";
      api = "openai-completions";
      compat = {
        supportsEagerToolInputStreaming = false;
        allowAnthropicHeaderOverrides = true;
      };
    };

    keybindings."app.session.new" = "ctrl+n";
    ssh.hosts.dev.host = "dev.invalid";
    skills.shared = "shared skill";
    commands.shared = "default command";
    rules.shared = "shared rule";
    agents.shared = "shared agent";
    prompts.shared = "shared prompt";
    instructions.shared = "shared instruction";
    themes.shared = "shared theme";
    tools.shared = "shared tool";
    hooks.pre.shared = "shared pre-hook";
    hooks.post.shared = "shared post-hook";
    agentsMd = "shared agents document";
    systemPrompt = "shared system prompt";
    rulesMd = "shared rules document";
    extensions."shared.ts" = "export default () => {};\n";
    lsp = {
      idleTimeoutMs = 12345;
      servers.nixd.disabled = true;
    };
    watchdog = {
      instructions = "Shared reviewer baseline";
      advisors = [
        {
          name = "Nix reviewer";
          model = "openai-codex/gpt-5.6-sol:xhigh";
          tools = [ ];
          instructions = "Review Nix module behavior.";
          enabled = false;
        }
      ];
    };
    appendSystemPrompt = "Append system fixture\n";
    titleSystemPrompt = "Title system fixture\n";
    watchdogPrompt = "Watchdog prompt fixture\n";

    profiles = {
      personal = { };

      work = {
        settings = {
          personality = null;
          task.disabledAgents = [ "oracle" ];
        };
        models.providers.local.baseUrl = "http://work.invalid";
        commands.shared = "work command";
        skills = lib.mkForce { };
        mcp.mcpServers.local = {
          type = "stdio";
          command = "local-mcp";
        };
      };

      "work-2.0_a".mcp = {
        "$schema" = "https://example.invalid/mcp-schema.json";
        mcpServers = { };
      };
    };
  };

  profileNameSucceeds =
    name:
    let
      evaluated = evaluate { profiles.${name} = { }; };
    in
    (builtins.tryEval (builtins.deepSeq evaluated.config.oh-my-pi.profiles true)).success;

  name64 = builtins.concatStringsSep "" (lib.replicate 64 "a");
  name65 = builtins.concatStringsSep "" (lib.replicate 65 "a");
  invalidProfileNames = [
    ""
    "."
    ".."
    "default"
    "Work"
    "../work"
    "work/team"
    "work."
    " work "
    "con"
    "lpt1.bak"
    name65
  ];
  validProfileNames = [
    "work-2.0_a"
    name64
  ];

  disabledFiles =
    (evaluate {
      enable = false;
      profiles.work.settings.personality = "pragmatic";
    }).config.home.file;

  emptyFiles =
    (evaluate {
      enable = true;
      profiles.personal = { };
    }).config.home.file;

  homeFiles = main.config.home.file;
  resourcePaths = [
    "AGENTS.md"
    "APPEND_SYSTEM.md"
    "RULES.md"
    "SYSTEM.md"
    "TITLE_SYSTEM.md"
    "WATCHDOG.md"
    "WATCHDOG.yml"
    "agents/shared.md"
    "extensions/shared.ts"
    "commands/shared.md"
    "config.yml"
    "hooks/post/shared"
    "hooks/pre/shared"
    "instructions/shared.md"
    "keybindings.yml"
    "lsp.json"
    "models.yml"
    "prompts/shared.md"
    "rules/shared.md"
    "skills/shared/SKILL.md"
    "ssh.json"
    "themes/shared"
    "tools/shared"
  ];
  prefixPaths = prefix: paths: map (path: "${prefix}/${path}") paths;
  expectedPaths = lib.sort builtins.lessThan (
    prefixPaths ".omp/agent" resourcePaths
    ++ prefixPaths ".omp/profiles/personal/agent" resourcePaths
    ++ prefixPaths ".omp/profiles/work/agent" (
      builtins.filter (path: path != "skills/shared/SKILL.md") resourcePaths
    )
    ++ [ ".omp/profiles/work/agent/mcp.json" ]
    ++ prefixPaths ".omp/profiles/work-2.0_a/agent" resourcePaths
    ++ [ ".omp/profiles/work-2.0_a/agent/mcp.json" ]
  );

  sharedFeatureFiles = sharedFeature.config.home.file;
  sharedDefaultConfig = sharedFeatureFiles.".omp/agent/config.yml".source;
  openaiProfileConfig = sharedFeatureFiles.".omp/profiles/openai/agent/config.yml".source;

  defaultConfig = homeFiles.".omp/agent/config.yml".source;
  personalConfig = homeFiles.".omp/profiles/personal/agent/config.yml".source;
  workConfig = homeFiles.".omp/profiles/work/agent/config.yml".source;
  defaultModels = homeFiles.".omp/agent/models.yml".source;
  workModels = homeFiles.".omp/profiles/work/agent/models.yml".source;
  workMcp = homeFiles.".omp/profiles/work/agent/mcp.json".source;
  work2Mcp = homeFiles.".omp/profiles/work-2.0_a/agent/mcp.json".source;
  defaultLsp = homeFiles.".omp/agent/lsp.json".source;
  personalLsp = homeFiles.".omp/profiles/personal/agent/lsp.json".source;
  workLsp = homeFiles.".omp/profiles/work/agent/lsp.json".source;
  defaultWatchdog = homeFiles.".omp/agent/WATCHDOG.yml".source;
  personalWatchdog = homeFiles.".omp/profiles/personal/agent/WATCHDOG.yml".source;
  workWatchdog = homeFiles.".omp/profiles/work/agent/WATCHDOG.yml".source;
  inlineResourceContents = {
    "extensions/shared.ts" = "export default () => {};\n";
    "APPEND_SYSTEM.md" = "Append system fixture\n";
    "TITLE_SYSTEM.md" = "Title system fixture\n";
    "WATCHDOG.md" = "Watchdog prompt fixture\n";
  };
  inheritedResourcePrefixes = [
    ".omp/agent"
    ".omp/profiles/personal/agent"
    ".omp/profiles/work/agent"
    ".omp/profiles/work-2.0_a/agent"
  ];
  workCommand =
    pkgs.writeText "work-command.md"
      homeFiles.".omp/profiles/work/agent/commands/shared.md".text;
  expectedWorkCommand = pkgs.writeText "expected-work-command.md" "work command";

  hasArtifactName = target: name: lib.hasSuffix "-${name}" (toString homeFiles.${target}.source);
in
assert lib.all (name: !(profileNameSucceeds name)) invalidProfileNames;
assert lib.all profileNameSucceeds validProfileNames;
assert disabledFiles == { };
assert emptyFiles == { };
assert builtins.attrNames homeFiles == expectedPaths;
assert builtins.hasAttr ".omp/profiles/personal/agent/skills/shared/SKILL.md" homeFiles;
assert !(builtins.hasAttr ".omp/profiles/work/agent/skills/shared/SKILL.md" homeFiles);
assert !(builtins.hasAttr ".omp/agent/mcp.json" homeFiles);
assert !(builtins.hasAttr ".omp/profiles/personal/agent/mcp.json" homeFiles);
assert homeFiles.".omp/profiles/work/agent/commands/shared.md".text == "work command";
assert lib.all (
  prefix:
  lib.all (relative: homeFiles."${prefix}/${relative}".text == inlineResourceContents.${relative}) (
    builtins.attrNames inlineResourceContents
  )
) inheritedResourcePrefixes;
assert builtins.hasAttr ".omp/agent/config.yml" sharedFeatureFiles;
assert builtins.hasAttr ".omp/profiles/openai/agent/config.yml" sharedFeatureFiles;
assert hasArtifactName ".omp/agent/config.yml" "omp-config.yml";
assert hasArtifactName ".omp/agent/models.yml" "omp-models.yml";
assert hasArtifactName ".omp/agent/keybindings.yml" "omp-keybindings.yml";
assert hasArtifactName ".omp/agent/ssh.json" "omp-ssh.json";
assert hasArtifactName ".omp/agent/lsp.json" "omp-lsp.json";
assert hasArtifactName ".omp/agent/WATCHDOG.yml" "omp-watchdog.yml";
assert hasArtifactName ".omp/profiles/work/agent/config.yml" "omp-profile-work-config.yml";
assert hasArtifactName ".omp/profiles/work/agent/models.yml" "omp-profile-work-models.yml";
assert hasArtifactName ".omp/profiles/work/agent/keybindings.yml"
  "omp-profile-work-keybindings.yml";
assert hasArtifactName ".omp/profiles/work/agent/ssh.json" "omp-profile-work-ssh.json";
assert hasArtifactName ".omp/profiles/work/agent/mcp.json" "omp-profile-work-mcp.json";
assert hasArtifactName ".omp/profiles/work/agent/lsp.json" "omp-profile-work-lsp.json";
assert hasArtifactName ".omp/profiles/work/agent/WATCHDOG.yml" "omp-profile-work-watchdog.yml";
pkgs.runCommand "oh-my-pi-profile-module-tests"
  {
    nativeBuildInputs = [
      pkgs.yq-go
      pkgs.jq
    ];
  }
  ''
    set -euo pipefail

    yq -e '.personality == "pragmatic"' ${defaultConfig} >/dev/null
    yq -e '.task.disabledAgents | join(",") == "scout,oracle"' ${defaultConfig} >/dev/null
    yq -e '.todo.remindersMax == 5' ${defaultConfig} >/dev/null
    yq -e 'has("todo") and (.todo | has("reminders") | not)' ${defaultConfig} >/dev/null
    yq -e '.dev.autoqaConsent == "granted"' ${defaultConfig} >/dev/null
    yq -e '.dev | has("autoqa") | not' ${defaultConfig} >/dev/null
    yq -e '.tools.xdev == false' ${defaultConfig} >/dev/null
    yq -e '.task.prewalk == true' ${defaultConfig} >/dev/null
    yq -e '.modelRoleStorage == "project"' ${defaultConfig} >/dev/null
    yq -e '.hindsight.requestTimeoutMs == 31000' ${defaultConfig} >/dev/null
    yq -e '.hindsight.reflectTimeoutMs == 121000' ${defaultConfig} >/dev/null
    yq -e '.hindsight.recallTimeoutMs == 32000' ${defaultConfig} >/dev/null
    yq -e '.hindsight.retainTimeoutMs == 61000' ${defaultConfig} >/dev/null
    yq -e '.providers.image == "openai-codex"' ${defaultConfig} >/dev/null
    yq -e '.providers.kimiApiFormat == "auto"' ${defaultConfig} >/dev/null
    yq -e '.tui.scrollbackRebuild == false' ${sharedDefaultConfig} >/dev/null
    yq -e '.tools == null or (.tools | has("discoveryMode") | not)' ${sharedDefaultConfig} >/dev/null
    yq -e 'has("modelRoleStorage") | not' ${sharedDefaultConfig} >/dev/null
    yq -e 'has("generate_image") | not' ${sharedDefaultConfig} >/dev/null
    yq -e '.providers.local.baseUrl == "http://default.invalid"' ${defaultModels} >/dev/null
    yq -e '.providers.local.api == "openai-completions"' ${defaultModels} >/dev/null
    yq -e '.providers.local.compat.supportsEagerToolInputStreaming == false' ${defaultModels} >/dev/null
    yq -e '.providers.local.compat.allowAnthropicHeaderOverrides == true' ${defaultModels} >/dev/null

    yq -e '.personality == "pragmatic"' ${personalConfig} >/dev/null
    yq -e '.modelRoleStorage == "project"' ${personalConfig} >/dev/null
    yq -e '.hindsight.requestTimeoutMs == 31000' ${personalConfig} >/dev/null
    yq -e '.hindsight.reflectTimeoutMs == 121000' ${personalConfig} >/dev/null
    yq -e '.hindsight.recallTimeoutMs == 32000' ${personalConfig} >/dev/null
    yq -e '.hindsight.retainTimeoutMs == 61000' ${personalConfig} >/dev/null
    yq -e '.providers.image == "openai-codex"' ${personalConfig} >/dev/null
    yq -e '.providers.kimiApiFormat == "auto"' ${personalConfig} >/dev/null
    yq -e 'has("personality") == false' ${workConfig} >/dev/null
    yq -e '.task.disabledAgents | join(",") == "oracle"' ${workConfig} >/dev/null
    yq -e '.providers.local.baseUrl == "http://work.invalid"' ${workModels} >/dev/null
    yq -e '.providers.local.api == "openai-completions"' ${workModels} >/dev/null
    yq -e '.providers.local.compat.supportsEagerToolInputStreaming == false' ${workModels} >/dev/null
    yq -e '.providers.local.compat.allowAnthropicHeaderOverrides == true' ${workModels} >/dev/null

    jq -e '. == {
      "idleTimeoutMs": 12345,
      "servers": {
        "nixd": {
          "disabled": true
        }
      }
    }' ${defaultLsp} >/dev/null
    cmp ${defaultLsp} ${personalLsp}

    yq -o=json '.' ${defaultWatchdog} \
      | jq -e '. == {
          "instructions": "Shared reviewer baseline",
          "advisors": [
            {
              "name": "Nix reviewer",
              "model": "openai-codex/gpt-5.6-sol:xhigh",
              "tools": [],
              "instructions": "Review Nix module behavior.",
              "enabled": false
            }
          ]
        }' >/dev/null
    cmp ${defaultWatchdog} ${personalWatchdog}

    cmp ${expectedWorkCommand} ${workCommand}

    jq -e --arg schema '${mcpSchemaUrl}' '."$schema" == $schema and .mcpServers.local.type == "stdio" and .mcpServers.local.command == "local-mcp"' ${workMcp} >/dev/null
    jq -e '."$schema" == "https://example.invalid/mcp-schema.json" and .mcpServers == {}' ${work2Mcp} >/dev/null

    yq -o=json '.modelRoles' ${openaiProfileConfig} \
      | jq -e '. == {
          "advisor": "openai-codex/gpt-5.6-sol:xhigh",
          "commit": "openai-codex/gpt-5.6-luna:medium",
          "default": "openai-codex/gpt-5.6-sol:xhigh",
          "designer": "openai-codex/gpt-5.6-sol:xhigh",
          "plan": "openai-codex/gpt-5.6-sol:xhigh",
          "slow": "openai-codex/gpt-5.6-sol:xhigh",
          "smol": "openai-codex/gpt-5.6-luna:medium",
          "task": "openai-codex/gpt-5.6-sol:xhigh",
          "tiny": "openai-codex/gpt-5.6-luna:medium",
          "vision": "openai-codex/gpt-5.6-sol:xhigh"
        }' >/dev/null

    mkdir -p "$out"
    cp ${defaultConfig} "$out/config.yml"
    cp ${defaultModels} "$out/models.yml"
    cp ${defaultLsp} "$out/lsp.json"
    cp ${defaultWatchdog} "$out/WATCHDOG.yml"
  ''
