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
      tui.scrollbackRebuild = false;
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
      task.isolation.mode = "auto";
      task.isolation.merge = "branch";
      task.disabledAgents = [ "librarian" ];
      edit.mode = "hashline";
      loop.mode = "reset";
      github.enabled = true;
      modelRoles = {
        default = "anthropic/claude-opus-5";
        smol = "anthropic/claude-haiku-4-5";
        slow = "anthropic/claude-opus-5:high";
        vision = "anthropic/claude-opus-5:high";
        plan = "anthropic/claude-opus-5:high";
        designer = "anthropic/claude-opus-5:high";
        commit = "anthropic/claude-sonnet-5:low";
        tiny = "anthropic/claude-haiku-4-5";
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
      pdf = "github:anthropics/skills/skills/pdf@b0cbd3df1533b396d281a6886d5132f623393a9c";
      pptx = "github:anthropics/skills/skills/pptx@b0cbd3df1533b396d281a6886d5132f623393a9c";
      frontend-design = "github:anthropics/skills/skills/frontend-design@b0cbd3df1533b396d281a6886d5132f623393a9c";
      web-artifacts-builder = "github:anthropics/skills/skills/web-artifacts-builder@b0cbd3df1533b396d281a6886d5132f623393a9c";
      uv = "github:wshobson/agents/plugins/python-development/skills/uv-package-manager@a6f0f457c4e41cbb0ad329b691d28e255a829210";
      rust-best-practices = "github:apollographql/skills/skills/rust-best-practices@5dca44919c9a320d5c0cec70ed5107d4d7a6a816";
      vitepress = "github:antfu/skills/skills/vitepress@c35a5588a5158b5b404a14fb10469b2b6dc1952b";
      no-slop = {
        src = noSlopSkill;
      };
    };
  };
}
