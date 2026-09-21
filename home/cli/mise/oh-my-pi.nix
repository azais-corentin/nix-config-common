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
  noSlopSkill = import ./no-slop-skill.nix pkgs;
  pythonProfilePaths = [
    ""
  ]
  ++ map (name: "/profiles/${name}") (builtins.attrNames config.oh-my-pi.profiles);
in
{
  programs.mise.globalConfig.tools."github:can1357/oh-my-pi".version = "latest";
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "github:can1357/oh-my-pi" ];

  # Puppeteer's downloaded Chrome lacks its runtime libraries on NixOS.
  programs.mise.globalConfig.env = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
    PUPPETEER_EXECUTABLE_PATH = lib.getExe pkgs.chromium;
  };

  # Provision each profile's managed fallback without selecting an interpreter.
  # Leaving python.interpreter unset preserves active/project venv precedence.
  # Keep existing environments so installed packages survive activation.
  #
  # uv ships alongside because omp exports the venv to the kernel (VIRTUAL_ENV
  # plus its bin/ on PATH), so a bare `uv pip install X` inside a cell targets
  # the managed env. The activation below uses the store path directly and does
  # not depend on this.
  home.packages = [ pkgs.uv ];

  home.activation.ompPythonEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    for omp_profile_path in ${lib.escapeShellArgs pythonProfilePaths}; do
      omp_python_root="$HOME/.omp$omp_profile_path"
      if [ -n "''${XDG_DATA_HOME:-}" ] && [ -d "$XDG_DATA_HOME/omp$omp_profile_path" ]; then
        omp_python_root="$XDG_DATA_HOME/omp$omp_profile_path"
      fi
      omp_python_env="$omp_python_root/python-env"
      if [ ! -x "$omp_python_env/bin/python" ]; then
        run ${pkgs.uv}/bin/uv venv --seed --managed-python --python 3.14 \
          "$omp_python_env"
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
      task.isolation.enabled = true;
      task.isolation.merge = "branch";
      task.disabledAgents = [ "librarian" ];
      edit.mode = "hashline";
      loop.mode = "reset";
      github.enabled = true;
      modelRoles = {
        default = "anthropic/claude-opus-5";
        smol = "anthropic/claude-sonnet-5:high";
        slow = "anthropic/claude-opus-5:high";
        vision = "anthropic/claude-opus-5:high";
        plan = "anthropic/claude-opus-5:high";
        commit = "anthropic/claude-sonnet-5:low";
        tiny = "anthropic/claude-sonnet-5:high";
        task = "anthropic/claude-opus-5:low";
        advisor = "anthropic/claude-opus-5:medium";
        image = "openai-codex/gpt-image-1";
        web = "google/gemini-3.8-flash-high";
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

    profiles.openai.settings.modelRoles = lib.mkForce {
      default = "openai-codex/gpt-6-astra:high";
      smol = "openai-codex/gpt-6-astra:low";
      slow = "openai-codex/gpt-6-astra:xhigh";
      vision = "openai-codex/gpt-6-astra:high";
      plan = "openai-codex/gpt-6-astra:xhigh";
      commit = "openai-codex/gpt-6-astra:low";
      tiny = "openai-codex/gpt-6-astra:low";
      task = "openai-codex/gpt-6-astra:high";
      advisor = "openai-codex/gpt-6-astra:xhigh";
    };
    profiles.openai.settings.compaction.thresholdPercent = 80;

    profiles.gemini.settings.modelRoles = lib.mkForce {
      default = "google-antigravity/gemini-3.8-flash:high";
      smol = "google-antigravity/gemini-3.8-flash:high";
      slow = "google-antigravity/gemini-3.8-flash:high";
      vision = "google-antigravity/gemini-3.8-flash:high";
      plan = "google-antigravity/gemini-3.8-flash:high";
      commit = "google-antigravity/gemini-3.8-flash:high";
      tiny = "google-antigravity/gemini-3.8-flash:high";
      task = "google-antigravity/gemini-3.8-flash:high";
      advisor = "google-antigravity/gemini-3.8-flash:high";
    };

    profiles.deepseek.settings.modelRoles = lib.mkForce {
      default = "openrouter/~deepseek/deepseek-flash-latest:high";
      smol = "openrouter/~deepseek/deepseek-flash-latest:high";
      slow = "openrouter/~deepseek/deepseek-flash-latest:high";
      plan = "openrouter/~deepseek/deepseek-flash-latest:high";
      commit = "openrouter/~deepseek/deepseek-flash-latest:high";
      tiny = "openrouter/~deepseek/deepseek-flash-latest:high";
      task = "openrouter/~deepseek/deepseek-flash-latest:high";
      advisor = "openrouter/~deepseek/deepseek-flash-latest:high";
    };

    skills = {
      pdf = "github:anthropics/skills/skills/pdf@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      pptx = "github:anthropics/skills/skills/pptx@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      frontend-design = "github:anthropics/skills/skills/frontend-design@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      web-artifacts-builder = "github:anthropics/skills/skills/web-artifacts-builder@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      uv = "github:wshobson/agents/plugins/python-development/skills/uv-package-manager@a30778f8c4e6b0a87567941b7cca4f534bf642b6";
      rust-best-practices = "github:apollographql/skills/skills/rust-best-practices@c288eb80629dd2309eed81f23d693f66a452d043";
      vitepress = "github:antfu/skills/skills/vitepress@a74f281a27dadc02397bc1a174b0f2c97531b6ae";
      boileau = "github:alxbd/boileau@5b272a70b1d5387984c12a08c4edc45af3f4fbda";
      no-slop = {
        src = noSlopSkill;
      };
    };
  };
}
