# Shared oh-my-pi base: the intersection of both consumers' settings. The
# module namespace is top-level `oh-my-pi.*` (declared in
# modules/home-manager/oh-my-pi). Consumers add their own secrets and provider
# credentials in a per-repo layer.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  pythonProfilePaths = [
    ""
  ]
  ++ map (name: "/profiles/${name}") (builtins.attrNames config.oh-my-pi.profiles);

  # One source per `mise run update:skills <target>`; the updater rewrites
  # rev and hash together.
  skillSrc = {
    anthropics = pkgs.fetchFromGitHub {
      owner = "anthropics";
      repo = "skills";
      rev = "e4bb5d960d87126ff3b3a8af1a104b7db67560ba";
      hash = "sha256-Gr9LatjawHHK9uKpoclWoiDHZ0NTpP3/4Pmeatl8p/Q=";
    };
    wshobson = pkgs.fetchFromGitHub {
      owner = "wshobson";
      repo = "agents";
      rev = "42203085cfc5736204bf0f6d436dff7e1da0bf3f";
      hash = "sha256-Azub9g+GEohos2XocajDJPAiQbdbfQFrn76AiDEGXmk=";
    };
    apollographql = pkgs.fetchFromGitHub {
      owner = "apollographql";
      repo = "skills";
      rev = "9dda1397730370aeb8df4ff8f2015c34c86b5003";
      hash = "sha256-TSGowC+gRHxPqhSvT1ySu+/yZPp4R2rbYWZ3V4IadcU=";
    };
    antfu = pkgs.fetchFromGitHub {
      owner = "antfu";
      repo = "skills";
      rev = "4a6bb39e7b45e26402eb215393c51ccf5df1ca4c";
      hash = "sha256-czc2Ai+Kg6qkgpJHEWMyOGRteuLMvhxxRiMuhDVjbBs=";
    };
  };
  skill = source: subdir: {
    src = skillSrc.${source};
    inherit subdir;
  };

  # Burn push for claude-usage-estimator; consumers without the flake input skip it.
  cueOmpExtension = lib.optional (
    pkgs ? inputs.claude-usage-estimator
  ) "${pkgs.inputs.claude-usage-estimator.omp-extension}";

  # `/modelpreset switch` replaces the whole modelRoles set (omitted roles are
  # cleared), so every preset restates the provider-independent roles.
  # `web` stays unset: omp's built-in search chain (Parallel, hosted, Exa, ...)
  # needs no credentials. The judge runs on Command Code credits.
  sharedRoles = {
    image = "openai-codex/gpt-image-2";
    judge = "commandcode/typesafe/jev";
  };

  # Startup roles, also published as the `claude` preset so a switch back
  # restores them without a rebuild.
  claudeRoles = sharedRoles // {
    default = "anthropic/claude-opus-5-5:high";
    slow = "anthropic/claude-opus-5-5:xhigh";
    plan = "anthropic/claude-fable-5-2:high";
    advisor = "anthropic/claude-fable-5-2:high";
    task = "anthropic/claude-opus-5-5:medium";
    vision = "anthropic/claude-fable-5-2:medium";
    # Backs the bundled scout and sonic agents. Sonnet 5.5 only pulls ahead at
    # high/max effort, where it spends more tokens than Opus.
    smol = "anthropic/claude-haiku-5-5:medium";
    tiny = "anthropic/claude-haiku-5-5:low";
    commit = "anthropic/claude-haiku-5-5:low";
    widget = "anthropic/claude-haiku-5-5";
  };

  claudeApiProvider = name: "claude-${name}";
  claudeApiProviders = lib.mapAttrs' (
    name: path:
    lib.nameValuePair (claudeApiProvider name) {
      baseUrl = "https://api.anthropic.com";
      api = "anthropic-messages";
      auth = "apiKey";
      apiKey = "!${lib.getExe' pkgs.coreutils "cat"} ${lib.escapeShellArg path}";
      # Discovery sends the resolved key as a bearer. The Messages client
      # uses its normal API-key auth.
      headers."anthropic-version" = "2026-10-21";
      discovery.type = "openai-models-list";
      models = map (id: { inherit id; }) [
        "claude-opus-5-5"
        "claude-sonnet-5-5"
        "claude-haiku-5-5"
      ];
    }
  ) config.oh-my-pi.claudeApiKeyFiles;
  claudeApiPresets = lib.mapAttrs' (
    name: _:
    lib.nameValuePair (claudeApiProvider name) {
      modelRoles = lib.mapAttrs (
        _: role:
        if lib.hasPrefix "anthropic/" role then
          "${claudeApiProvider name}/${lib.removePrefix "anthropic/" role}"
        else
          role
      ) claudeRoles;
    }
  ) config.oh-my-pi.claudeApiKeyFiles;
in
{
  imports = [
    ../../../modules/home-manager/oh-my-pi
    {
      options.oh-my-pi.claudeApiKeyFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Claude API preset suffixes mapped to private runtime secret file paths.";
      };
    }
  ];

  programs.mise.globalConfig.tools."github:can1357/oh-my-pi".version = "latest";
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "github:can1357/oh-my-pi" ];

  # omp has no browser-executable setting; this env var wins over PATH
  # discovery and the Chrome-for-Testing download (missing libs on NixOS).
  programs.mise.globalConfig.env.PUPPETEER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;

  # Each profile's managed fallback env (omp's discovery after VIRTUAL_ENV and
  # project venvs; python.interpreter stays unset so those keep precedence).
  # The paths mirror omp's own: ~/.omp[/profiles/<name>]/python-env, or the
  # XDG_DATA_HOME equivalent when that directory exists.
  #
  # uv ships alongside because omp exports the venv to the kernel (VIRTUAL_ENV
  # plus its bin/ on PATH), so a bare `uv pip install X` inside a cell targets
  # the managed env. The activation below uses the store path directly and does
  # not depend on this.
  # omp-at runs any oh-my-pi git version from source (see ./omp-at.nix).
  home.packages = [
    pkgs.uv
    (import ./omp-at.nix pkgs)
  ];

  home.activation.ompPythonEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Writable per-profile venv (so %pip / uv pip keep working) built on the
    # Nix interpreter: no CPython download, no nix-ld. Recreated when the Nix
    # Python store path changes (pyvenv.cfg `home`), which drops installed pkgs.
    omp_python_home=${pkgs.python3}/bin
    for omp_profile_path in ${lib.escapeShellArgs pythonProfilePaths}; do
      omp_python_root="$HOME/.omp$omp_profile_path"
      if [ -n "''${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/omp$omp_profile_path" ]; then
        omp_python_root="$XDG_DATA_HOME/omp$omp_profile_path"
      fi
      omp_python_env="$omp_python_root/python-env"
      if [ -e "$omp_python_env/pyvenv.cfg" ] && ! grep -qxF "home = $omp_python_home" "$omp_python_env/pyvenv.cfg"; then
        run rm -rf "$omp_python_env"
      fi
      if [ ! -x "$omp_python_env/bin/python" ]; then
        run ${pkgs.uv}/bin/uv venv --seed --no-managed-python --python ${pkgs.python3.interpreter} "$omp_python_env"
      fi
    done
  '';

  oh-my-pi = {
    enable = true;
    models.providers = claudeApiProviders;

    settings = {
      providers.anthropic.serverSideFallback = true;
      theme = {
        dark = "dark-nebula";
        light = "light";
      };
      symbolPreset = "nerd";
      showHardwareCursor = true;
      statusLine = {
        preset = "default";
        separator = "powerline-thin";
        sessionAccent = true;
        showHookStatus = true;
        transparent = true;
      };
      composer.shape = "borderless";
      composer.tokenRate = true;
      composer.recallClearedDrafts = false;
      compaction.dropUseless = true;
      compaction.thresholdPercent = 50;
      # Give Codex models more of their context window before compacting.
      compaction.modelThresholds."openai-codex/*" = "80%";
      # Haiku 5.5's 100k window is its pricing-tier boundary (prompts past it
      # cost 5x): compact just under it instead of at 50k.
      compaction.modelThresholds."anthropic/claude-haiku-5-5" = "90%";
      terminal.showImages = true;
      terminal.showProgress = true;
      images = {
        autoResize = true;
        blockImages = false;
        urls.enabled = true;
      };
      generate_image.enabled = true;
      tui.hyperlinks = "auto";
      tui.tight = true;
      tui.renderMermaid = true;
      tui.reactions = false;
      display = {
        shimmer = "kitt";
        showTokenUsage = false;
        subagentLivePreview = true;
        cacheMissMarker = true;
      };
      title.icons = "boring";
      # Every 10 prompts the judge re-checks that a generated title still fits.
      title.refreshAfterPrompts = 10;
      recap = {
        enabled = true;
        idleSeconds = 180;
      };
      startup = {
        setupWizard = false;
        showSplash = false;
      };
      error.notify = "on";
      plan.autosave = true;
      task.showResolvedModelBadge = false;
      task.enableEffort = true;
      # Caller `effort: "hi"` maps to the model's top tier (max on Claude);
      # cap spawns at high so neither med nor hi escalates past it.
      task.maxEffort = "high";
      task.perCallModel = "on";
      task.isolation.enabled = true;
      task.isolation.merge = "branch";
      task.disabledAgents = [ "librarian" ];
      edit.mode = "hashline";
      loop.mode = "reset";
      github.enabled = true;
      astGrep.enabled = true;
      # Inside a Tern pane, browser tabs open as picture-in-pictures over omp's
      # pane; elsewhere omp keeps using headless Chromium.
      browser.tern = true;
      modelRoles = claudeRoles;
      # Switch with `/modelpreset switch <name>`; the next rebuild restores
      # the claude roles above.
      modelPresets = claudeApiPresets // {
        claude.modelRoles = claudeRoles;
        gpt.modelRoles = sharedRoles // {
          default = "openai-codex/gpt-6.2-sol:high";
          slow = "openai-codex/gpt-6.2-sol:high";
          plan = "openai-codex/gpt-6.2-sol:high";
          advisor = "openai-codex/gpt-6.2-sol:high";
          task = "openai-codex/gpt-6.2-sol:medium";
          vision = "openai-codex/gpt-6.2-sol:medium";
          smol = "openai-codex/gpt-6-luna:medium";
          tiny = "openai-codex/gpt-6-luna:low";
          commit = "openai-codex/gpt-6-luna:low";
        };
        gemini.modelRoles = sharedRoles // {
          default = "antigravity-cli/gemini-4-hydrogen:high";
          slow = "antigravity-cli/gemini-4-hydrogen:high";
          plan = "antigravity-cli/gemini-4-hydrogen:high";
          advisor = "antigravity-cli/gemini-4-hydrogen:high";
          task = "antigravity-cli/gemini-4-hydrogen:high";
          vision = "antigravity-cli/gemini-4-hydrogen:high";
          smol = "antigravity-cli/gemini-4-hydrogen:low";
          commit = "antigravity-cli/gemini-4-hydrogen:low";
          tiny = "antigravity-cli/gemini-4-hydrogen:low";
        };
        deepseek.modelRoles = sharedRoles // {
          slow = "commandcode/deepseek/deepseek-v4.1-flash:max";
          plan = "commandcode/deepseek/deepseek-v4.1-flash:max";
          default = "commandcode/deepseek/deepseek-v4.1-flash:high";
          advisor = "commandcode/deepseek/deepseek-v4.1-flash:high";
          task = "commandcode/deepseek/deepseek-v4.1-flash:high";
          vision = "commandcode/deepseek/deepseek-v4.1-flash:high";
          smol = "commandcode/deepseek/deepseek-v4.1-flash:low";
          tiny = "commandcode/deepseek/deepseek-v4.1-flash:low";
          commit = "commandcode/deepseek/deepseek-v4.1-flash:low";
        };
      };
      personality = "pragmatic";
      memory.backend = "mnemopi";
      mnemopi = {
        scoping = "per-project-tagged";
        autoRecall = true;
        autoRetain = true;
        embeddingVariant = "en";
        llmMode = "smol";
        polyphonicRecall = true;
        enhancedRecall = true;
        proactiveLinking = true;
      };
      autolearn.enabled = false;
      extensions = cueOmpExtension;
    };

    skills = {
      pdf = skill "anthropics" "skills/pdf";
      pptx = skill "anthropics" "skills/pptx";
      frontend-design = skill "anthropics" "skills/frontend-design";
      web-artifacts-builder = skill "anthropics" "skills/web-artifacts-builder";
      uv = skill "wshobson" "plugins/python-development/skills/uv-package-manager";
      rust-best-practices = skill "apollographql" "skills/rust-best-practices";
      vitepress = skill "antfu" "skills/vitepress";
    };
  };
}
