# Shared oh-my-pi base: the intersection of both consumers' settings. The
# module namespace is top-level `oh-my-pi.*` (declared in
# modules/home-manager/oh-my-pi). Consumers add their own secrets and provider
# credentials in a per-repo layer.
{ lib, pkgs, ... }:
let
  noSlopSkill = import ./no-slop-skill.nix pkgs;
in
{
  programs.mise.globalConfig.tools."github:can1357/oh-my-pi".version = "latest";
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "github:can1357/oh-my-pi" ];

  # omp's eval tool needs a Python 3.8+ interpreter. It resolves one from an
  # active/project venv, then ~/.omp/python-env, then PATH; NixOS ships no
  # global python, so provision that managed venv with uv. Seeded with pip so
  # the in-cell `%pip` magic works. `python.interpreter` is deliberately left
  # unset — setting it disables discovery, which would stop a project's own
  # .venv from winning. Created only when absent, so packages a session
  # installs survive rebuilds.
  #
  # uv ships alongside because omp exports the venv to the kernel (VIRTUAL_ENV
  # plus its bin/ on PATH), so a bare `uv pip install X` inside a cell targets
  # the managed env. The activation below uses the store path directly and does
  # not depend on this.
  home.packages = [ pkgs.uv ];

  home.activation.ompPythonEnv = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ ! -x "$HOME/.omp/python-env/bin/python" ]; then
      run ${pkgs.uv}/bin/uv venv --seed --managed-python --python 3.14 \
        "$HOME/.omp/python-env" \
        || echo "omp: could not create ~/.omp/python-env; the Python kernel stays unavailable"
    fi
  '';

  oh-my-pi = {
    enable = true;

    settings = {
      providers = {
        tinyModel = "online";
        anthropic.serverSideFallback = true;
        webSearchGeminiModel = "gemini-3.7-flash-low";
      };
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
      compaction.dropUseless = true;
      compaction.thresholdPercent = 50;
      terminal.showImages = true;
      terminal.showProgress = true;
      images = {
        autoResize = true;
        blockImages = false;
      };
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
      task.isolation.mode = "auto";
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
        designer = "anthropic/claude-opus-5:high";
        commit = "anthropic/claude-sonnet-5:low";
        tiny = "anthropic/claude-sonnet-5:high";
        task = "anthropic/claude-opus-5:low";
        advisor = "anthropic/claude-opus-5:medium";
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
      default = "openai-codex/gpt-5.6-sol:xhigh";
      smol = "openai-codex/gpt-5.6-luna:medium";
      slow = "openai-codex/gpt-5.6-sol:xhigh";
      vision = "openai-codex/gpt-5.6-sol:xhigh";
      plan = "openai-codex/gpt-5.6-sol:xhigh";
      designer = "openai-codex/gpt-5.6-sol:xhigh";
      commit = "openai-codex/gpt-5.6-luna:medium";
      tiny = "openai-codex/gpt-5.6-luna:medium";
      task = "openai-codex/gpt-5.6-sol:xhigh";
      advisor = "openai-codex/gpt-5.6-sol:xhigh";
    };

    profiles.gemini.settings.modelRoles = lib.mkForce {
      default = "google-antigravity/gemini-3.7-flash:high";
      smol = "google-antigravity/gemini-3.7-flash:high";
      slow = "google-antigravity/gemini-3.7-flash:high";
      vision = "google-antigravity/gemini-3.7-flash:high";
      plan = "google-antigravity/gemini-3.7-flash:high";
      designer = "google-antigravity/gemini-3.7-flash:high";
      commit = "google-antigravity/gemini-3.7-flash:high";
      tiny = "google-antigravity/gemini-3.7-flash:high";
      task = "google-antigravity/gemini-3.7-flash:high";
      advisor = "google-antigravity/gemini-3.7-flash:high";
    };

    profiles.deepseek.settings.modelRoles = lib.mkForce {
      default = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      smol = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      slow = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      plan = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      designer = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      commit = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      tiny = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      task = "openrouter/deepseek/deepseek-v4-flash-0731:high";
      advisor = "openrouter/deepseek/deepseek-v4-flash-0731:high";
    };

    skills = {
      pdf = "github:anthropics/skills/skills/pdf@3b3fad96af16a10759d930941b4520ba0c40edae";
      pptx = "github:anthropics/skills/skills/pptx@3b3fad96af16a10759d930941b4520ba0c40edae";
      frontend-design = "github:anthropics/skills/skills/frontend-design@3b3fad96af16a10759d930941b4520ba0c40edae";
      web-artifacts-builder = "github:anthropics/skills/skills/web-artifacts-builder@3b3fad96af16a10759d930941b4520ba0c40edae";
      uv = "github:wshobson/agents/plugins/python-development/skills/uv-package-manager@38e19c20d2b154510b0e624a2e3e186b19b5c527";
      rust-best-practices = "github:apollographql/skills/skills/rust-best-practices@c288eb80629dd2309eed81f23d693f66a452d043";
      vitepress = "github:antfu/skills/skills/vitepress@a74f281a27dadc02397bc1a174b0f2c97531b6ae";
      boileau = "github:alxbd/boileau@5b272a70b1d5387984c12a08c4edc45af3f4fbda";
      no-slop = {
        src = noSlopSkill;
      };
    };
  };
}
