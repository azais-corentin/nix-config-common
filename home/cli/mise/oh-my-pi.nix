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
      rev = "8a1541c4a3ffa5a20a5a91de0dcf3f0bab1d1ef4";
      hash = "sha256-PRBkTEGNwT73EFCvuTprzIBGiG+UGSYiaCkY7Ji13us=";
    };
    wshobson = pkgs.fetchFromGitHub {
      owner = "wshobson";
      repo = "agents";
      rev = "156b7a5e7a8b93642628a339ee4039c925b34c7f";
      hash = "sha256-LNDpYF5bOeG9GmDW3A2sZv88B00WmxxOAPkzCgkfj3Y=";
    };
    apollographql = pkgs.fetchFromGitHub {
      owner = "apollographql";
      repo = "skills";
      rev = "222dfc07720227bd0f330bd1b45a9741b1c97bee";
      hash = "sha256-RHi4tNHB61F961u7vEnOyoEIzHbvG/O7gG03yLwX4Po=";
    };
    antfu = pkgs.fetchFromGitHub {
      owner = "antfu";
      repo = "skills";
      rev = "e53a142a2420e8cd812cfe9ed0484ab01bc856aa";
      hash = "sha256-+o01pcuRdtLwkKhHLArOazFYiSvWaWhQXijld54Yn5U=";
    };
  };
  skill = source: subdir: {
    src = skillSrc.${source};
    inherit subdir;
  };

  # `mise run update:apps omp-telegram` rewrites url and hash together. The
  # npm tarball needs no install: omp maps its peer imports onto host copies.
  ompTelegram = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@tickernelz/omp-telegram/-/omp-telegram-0.6.16.tgz";
    hash = "sha256-nHhjMXHEgxAqgex8UacVBNHm40NfFPZ+gScmE/hincQ=";
  };

  # Burn push for claude-usage-estimator; consumers without the flake input skip it.
  cueOmpExtension = lib.optional (
    pkgs ? inputs.claude-usage-estimator
  ) "${pkgs.inputs.claude-usage-estimator.omp-extension}";

  # `/modelpreset switch` replaces the whole modelRoles set (omitted roles are
  # cleared), so every preset restates the provider-independent roles.
  sharedRoles = {
    image = "openai-codex/gpt-image-2";
    web = "google-antigravity/gemini-3.8-flash";
  };

  # Startup roles, also published as the `claude` preset so a switch back
  # restores them without a rebuild.
  claudeRoles = sharedRoles // {
    default = "anthropic/claude-opus-5-5:high";
    slow = "anthropic/claude-opus-5-5:high";
    plan = "anthropic/claude-opus-5-5:high";
    advisor = "anthropic/claude-opus-5-5:high";
    task = "anthropic/claude-opus-5-5:medium";
    vision = "anthropic/claude-opus-5-5:medium";
    smol = "anthropic/claude-sonnet-5-5:medium";
    tiny = "anthropic/claude-sonnet-5-5:low";
    commit = "anthropic/claude-sonnet-5-5:low";
  };
in
{
  imports = [ ../../../modules/home-manager/oh-my-pi ];

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
      terminal.showImages = true;
      terminal.showProgress = true;
      images = {
        autoResize = true;
        blockImages = false;
      };
      generate_image.enabled = true;
      tui.hyperlinks = "auto";
      tui.tight = true;
      tui.renderMermaid = true;
      display = {
        shimmer = "kitt";
        showTokenUsage = false;
        subagentLivePreview = true;
      };
      recap = {
        enabled = true;
        idleSeconds = 180;
      };
      startup = {
        setupWizard = false;
        showSplash = false;
      };
      task.showResolvedModelBadge = false;
      task.enableEffort = true;
      # Caller `effort: "hi"` maps to the model's top tier (max on Claude);
      # cap spawns at high so neither med nor hi escalates past it.
      task.maxEffort = "high";
      task.isolation.enabled = true;
      task.isolation.merge = "branch";
      task.disabledAgents = [ "librarian" ];
      edit.mode = "hashline";
      loop.mode = "reset";
      github.enabled = true;
      modelRoles = claudeRoles;
      # Switch with `/modelpreset switch <name>`; the next rebuild restores
      # the claude roles above.
      modelPresets = {
        claude.modelRoles = claudeRoles;
        gpt.modelRoles = sharedRoles // {
          default = "openai-codex/gpt-6.1-sol:high";
          slow = "openai-codex/gpt-6.1-sol:high";
          plan = "openai-codex/gpt-6.1-sol:high";
          advisor = "openai-codex/gpt-6.1-sol:high";
          task = "openai-codex/gpt-6.1-sol:medium";
          vision = "openai-codex/gpt-6.1-sol:medium";
          smol = "openai-codex/gpt-6-luna:medium";
          tiny = "openai-codex/gpt-6-luna:low";
          commit = "openai-codex/gpt-6-luna:low";
        };
        gemini.modelRoles = sharedRoles // {
          default = "google-antigravity/gemini-3.8-flash:high";
          slow = "google-antigravity/gemini-3.8-flash:high";
          plan = "google-antigravity/gemini-3.8-flash:high";
          advisor = "google-antigravity/gemini-3.8-flash:high";
          task = "google-antigravity/gemini-3.8-flash:high";
          vision = "google-antigravity/gemini-3.8-flash:high";
          smol = "google-antigravity/gemini-3.8-flash:low";
          commit = "google-antigravity/gemini-3.8-flash:low";
          tiny = "google-antigravity/gemini-3.8-flash:minimal";
        };
        deepseek.modelRoles = sharedRoles // {
          slow = "openrouter/~deepseek/deepseek-flash-latest:max";
          plan = "openrouter/~deepseek/deepseek-flash-latest:max";
          default = "openrouter/~deepseek/deepseek-flash-latest:high";
          advisor = "openrouter/~deepseek/deepseek-flash-latest:high";
          task = "openrouter/~deepseek/deepseek-flash-latest:high";
          vision = "openrouter/~deepseek/deepseek-flash-latest:high";
          smol = "openrouter/~deepseek/deepseek-flash-latest:low";
          tiny = "openrouter/~deepseek/deepseek-flash-latest:low";
          commit = "openrouter/~deepseek/deepseek-flash-latest:low";
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
      # Telegram bridge; tokens are per consumer (telegram.json / env).
      extensions = [ "${ompTelegram}" ] ++ cueOmpExtension;
    };

    rules.no-find-from-root = lib.removeSuffix "\n" ''
      ---
      name: no-find-from-root
      description: "Never run `find /` — scanning from the filesystem root is forbidden; use a scoped path or the `find` tool"
      condition: "\\bfind\\s+/(?:\\s|$)"
      scope: "tool:bash"
      ---

      Never invoke `find /` (scanning from the filesystem root). It is slow, noisy, and traverses the entire system. Scope the search to a concrete directory (e.g. `find ~/.cargo/registry/src -maxdepth 2 ...`) or, preferably, use the dedicated `find` tool with explicit `paths` globs. If you need a known cache/registry location, target it directly instead of walking root.
    '';

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
