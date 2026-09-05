let
  flake = builtins.getFlake (toString ../../..);
  pkgs = flake.inputs.nixpkgs.legacyPackages.${builtins.currentSystem};
  inherit (pkgs) lib;

  mcpSchemaUrl = "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json";

  # The shared feature is a real home-manager module: besides home.file it also
  # declares home.packages and a home.activation DAG entry. This harness runs on
  # bare lib.evalModules, so stand in for the home-manager options it touches and
  # for lib.hm.dag (same entry shape as home-manager's modules/lib/dag.nix).
  homeModule = { lib, ... }: {
    options.home = {
      file = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
      activation = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };

  hmLib = lib.extend (
    _: _: {
      hm.dag = {
        entryAnywhere = data: {
          inherit data;
          before = [ ];
          after = [ ];
        };
        entryAfter = after: data: {
          inherit data after;
          before = [ ];
        };
        entryBefore = before: data: {
          inherit data before;
          after = [ ];
        };
      };
    }
  );

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
        homeModule
        { oh-my-pi = declaration; }
      ];
    };

  sharedFeature = lib.evalModules {
    specialArgs = {
      inherit pkgs;
      lib = hmLib;
    };
    modules = [
      ./default.nix
      homeModule
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
        imageOrder = [ "openai-codex" ];
        kimiApiFormat = "auto";
        "openai-codex".codeMode = "auto";
      };
      computer.enabled = true;
      tui.titleState = false;
      workspace.additionalDirectories = [ "/tmp/x" ];
      bash.direnv = "off";
      retry.usageReservePolicy = "auto";
      tui.resizeScrollback = "append";
      edit.mode = "sloppy";
      edit.autoRepair.enabled = true;
      task.agentAdvisor.scout = "off";
      compaction.methodOrder = [
        "snapcompact"
        "soft"
      ];
      features.unexpectedStopDetection = "smart";
    };

    models.providers.local = {
      baseUrl = "http://default.invalid";
      api = "openai-completions";
      compat = {
        supportsEagerToolInputStreaming = false;
        allowAnthropicHeaderOverrides = true;
        supportsContextManagement = true;
      };
      guardrailTrace = "enabled";
      discovery = {
        type = "openai-models-list";
        injectV1 = false;
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
    personalityPrompt = "Personality fixture\n";
    dap.adapters.custom-gdb = {
      command = "gdb";
      args = [ "--interpreter=dap" ];
      languages = [
        "c"
        "cpp"
      ];
      fileTypes = [
        "c"
        "cpp"
      ];
      rootMarkers = [ "CMakeLists.txt" ];
      launchDefaults.stopAtEntry = false;
      attachDefaults.skipAttachRequest = true;
      connectMode = "tcp";
      acceptsDirectoryProgram = true;
    };

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
          env.TOKEN = "local";
          requestIdFormat = "string";
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

  mcpServerSucceeds =
    server:
    let
      evaluated = evaluate { profiles.probe.mcp.mcpServers.probe = server; };
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
    "PERSONALITY.md"
    "RULES.md"
    "SYSTEM.md"
    "TITLE_SYSTEM.md"
    "WATCHDOG.md"
    "WATCHDOG.yml"
    "agents/shared.md"
    "extensions/shared.ts"
    "commands/shared.md"
    "config.yml"
    "dap.json"
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
  sharedRulePaths = [
    ".omp/agent/rules/no-find-from-root.md"
    ".omp/profiles/openai/agent/rules/no-find-from-root.md"
    ".omp/profiles/deepseek/agent/rules/no-find-from-root.md"
  ];
  sharedNoFindRule = sharedFeatureFiles.".omp/agent/rules/no-find-from-root.md".text;
  sharedDefaultConfig = sharedFeatureFiles.".omp/agent/config.yml".source;

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
  defaultDap = homeFiles.".omp/agent/dap.json".source;
  personalDap = homeFiles.".omp/profiles/personal/agent/dap.json".source;
  defaultWatchdog = homeFiles.".omp/agent/WATCHDOG.yml".source;
  personalWatchdog = homeFiles.".omp/profiles/personal/agent/WATCHDOG.yml".source;
  workWatchdog = homeFiles.".omp/profiles/work/agent/WATCHDOG.yml".source;
  inlineResourceContents = {
    "extensions/shared.ts" = "export default () => {};\n";
    "APPEND_SYSTEM.md" = "Append system fixture\n";
    "PERSONALITY.md" = "Personality fixture\n";
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
assert mcpServerSucceeds { command = "local-mcp"; };
assert
  !(mcpServerSucceeds {
    type = "http";
    command = "local-mcp";
  });
assert
  !(mcpServerSucceeds {
    type = "http";
    url = null;
  });
assert
  !(mcpServerSucceeds {
    type = "stdio";
    command = "local-mcp";
    url = "http://local.invalid";
  });
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
assert lib.all (path: builtins.hasAttr path sharedFeatureFiles) sharedRulePaths;
assert lib.all (path: sharedFeatureFiles.${path}.text == sharedNoFindRule) sharedRulePaths;
assert lib.hasInfix ''condition: "\\bfind\\s+/(?:\\s|$)"'' sharedNoFindRule;
assert lib.hasInfix ''scope: "tool:bash"'' sharedNoFindRule;
assert hasArtifactName ".omp/agent/config.yml" "omp-config.yml";
assert hasArtifactName ".omp/agent/models.yml" "omp-models.yml";
assert hasArtifactName ".omp/agent/keybindings.yml" "omp-keybindings.yml";
assert hasArtifactName ".omp/agent/ssh.json" "omp-ssh.json";
assert hasArtifactName ".omp/agent/lsp.json" "omp-lsp.json";
assert hasArtifactName ".omp/agent/dap.json" "omp-dap.json";
assert hasArtifactName ".omp/agent/WATCHDOG.yml" "omp-watchdog.yml";
assert hasArtifactName ".omp/profiles/work/agent/config.yml" "omp-profile-work-config.yml";
assert hasArtifactName ".omp/profiles/work/agent/models.yml" "omp-profile-work-models.yml";
assert hasArtifactName ".omp/profiles/work/agent/keybindings.yml"
  "omp-profile-work-keybindings.yml";
assert hasArtifactName ".omp/profiles/work/agent/ssh.json" "omp-profile-work-ssh.json";
assert hasArtifactName ".omp/profiles/work/agent/mcp.json" "omp-profile-work-mcp.json";
assert hasArtifactName ".omp/profiles/work/agent/lsp.json" "omp-profile-work-lsp.json";
assert hasArtifactName ".omp/profiles/work/agent/dap.json" "omp-profile-work-dap.json";
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
    yq -e '.providers.imageOrder | join(",") == "openai-codex"' ${defaultConfig} >/dev/null
    yq -e '.providers.kimiApiFormat == "auto"' ${defaultConfig} >/dev/null
    yq -e '.computer.enabled == true' ${defaultConfig} >/dev/null
    yq -e '.tui.titleState == false' ${defaultConfig} >/dev/null
    yq -e '.workspace.additionalDirectories | join(",") == "/tmp/x"' ${defaultConfig} >/dev/null
    yq -e '.bash.direnv == "off"' ${defaultConfig} >/dev/null
    yq -e '.retry.usageReservePolicy == "auto"' ${defaultConfig} >/dev/null
    yq -e '.tui.resizeScrollback == "append"' ${defaultConfig} >/dev/null
    yq -e '.edit.mode == "sloppy"' ${defaultConfig} >/dev/null
    yq -e '.edit.autoRepair.enabled == true' ${defaultConfig} >/dev/null
    yq -e '.task.agentAdvisor.scout == "off"' ${defaultConfig} >/dev/null
    yq -e '.compaction.methodOrder | join(",") == "snapcompact,soft"' ${defaultConfig} >/dev/null
    yq -e '.providers["openai-codex"].codeMode == "auto"' ${defaultConfig} >/dev/null
    yq -e '.features.unexpectedStopDetection == "smart"' ${defaultConfig} >/dev/null
    yq -e '.compaction | has("strategy") | not' ${defaultConfig} >/dev/null
    yq -e '.tui | has("scrollbackRebuild") | not' ${defaultConfig} >/dev/null
    yq -e '.tui | has("scrollbackRebuild") | not' ${sharedDefaultConfig} >/dev/null
    yq -e '.task.enableEffort == true' ${sharedDefaultConfig} >/dev/null
    yq -e '.composer.shape == "borderless"' ${sharedDefaultConfig} >/dev/null
    yq -e '.tools == null or (.tools | has("discoveryMode") | not)' ${sharedDefaultConfig} >/dev/null
    yq -e 'has("modelRoleStorage") | not' ${sharedDefaultConfig} >/dev/null
    yq -e 'has("generate_image") | not' ${sharedDefaultConfig} >/dev/null
    yq -e '.providers.local.baseUrl == "http://default.invalid"' ${defaultModels} >/dev/null
    yq -e '.providers.local.api == "openai-completions"' ${defaultModels} >/dev/null
    yq -e '.providers.local.compat.supportsEagerToolInputStreaming == false' ${defaultModels} >/dev/null
    yq -e '.providers.local.compat.allowAnthropicHeaderOverrides == true' ${defaultModels} >/dev/null
    yq -e '.providers.local.compat.supportsContextManagement == true' ${defaultModels} >/dev/null
    yq -e '.providers.local.guardrailTrace == "enabled"' ${defaultModels} >/dev/null
    yq -e '.providers.local.discovery.injectV1 == false' ${defaultModels} >/dev/null
    yq -e '.providers.local.discovery.type == "openai-models-list"' ${defaultModels} >/dev/null

    yq -e '.personality == "pragmatic"' ${personalConfig} >/dev/null
    yq -e '.modelRoleStorage == "project"' ${personalConfig} >/dev/null
    yq -e '.hindsight.requestTimeoutMs == 31000' ${personalConfig} >/dev/null
    yq -e '.hindsight.reflectTimeoutMs == 121000' ${personalConfig} >/dev/null
    yq -e '.hindsight.recallTimeoutMs == 32000' ${personalConfig} >/dev/null
    yq -e '.hindsight.retainTimeoutMs == 61000' ${personalConfig} >/dev/null
    yq -e '.providers.imageOrder | join(",") == "openai-codex"' ${personalConfig} >/dev/null
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

    jq -e '. == {
      "adapters": {
        "custom-gdb": {
          "command": "gdb",
          "args": ["--interpreter=dap"],
          "languages": ["c", "cpp"],
          "fileTypes": ["c", "cpp"],
          "rootMarkers": ["CMakeLists.txt"],
          "launchDefaults": { "stopAtEntry": false },
          "attachDefaults": { "skipAttachRequest": true },
          "connectMode": "tcp",
          "acceptsDirectoryProgram": true
        }
      }
    }' ${defaultDap} >/dev/null
    cmp ${defaultDap} ${personalDap}

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

    jq -e --arg schema '${mcpSchemaUrl}' '."$schema" == $schema and .mcpServers.local == { "type": "stdio", "command": "local-mcp", "env": { "TOKEN": "local" }, "requestIdFormat": "string" }' ${workMcp} >/dev/null
    jq -e '."$schema" == "https://example.invalid/mcp-schema.json" and .mcpServers == {}' ${work2Mcp} >/dev/null

    mkdir -p "$out"
    cp ${defaultConfig} "$out/config.yml"
    cp ${defaultModels} "$out/models.yml"
    cp ${defaultLsp} "$out/lsp.json"
    cp ${defaultDap} "$out/dap.json"
    cp ${defaultWatchdog} "$out/WATCHDOG.yml"
  ''
