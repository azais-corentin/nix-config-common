# Shared oh-my-pi base: the intersection of both consumers' settings. The
# module namespace is top-level `oh-my-pi.*` (declared in
# modules/home-manager/oh-my-pi). Consumers add their own secrets and provider
# credentials in a per-repo layer.
{ lib, ... }:
{
  programs.mise.globalConfig.tools."github:can1357/oh-my-pi".version = "latest";
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "github:can1357/oh-my-pi" ];

  oh-my-pi = {
    enable = true;

    settings = {
      providers = {
        webSearch = "auto";
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
      terminal.showImages = true;
      terminal.showProgress = true;
      images = {
        autoResize = true;
        blockImages = false;
      };
      tui.hyperlinks = "auto";
      tui.tight = true;
      tui.renderMermaid = true;
      tui.scrollbackRebuild = true;
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
        default = "anthropic/claude-opus-4-8";
        smol = "anthropic/claude-haiku-4-5";
        slow = "anthropic/claude-fable-5:high";
        vision = "anthropic/claude-fable-5:high";
        plan = "anthropic/claude-fable-5:high";
        designer = "anthropic/claude-fable-5:high";
        commit = "anthropic/claude-sonnet-5:low";
        tiny = "anthropic/claude-haiku-4-5";
        task = "anthropic/claude-opus-4-8:low";
        advisor = "openai-codex/gpt-5.5";
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

    skills = {
      pdf = "github:anthropics/skills/skills/pdf@b0cbd3df1533b396d281a6886d5132f623393a9c";
      pptx = "github:anthropics/skills/skills/pptx@b0cbd3df1533b396d281a6886d5132f623393a9c";
      frontend-design = "github:anthropics/skills/skills/frontend-design@b0cbd3df1533b396d281a6886d5132f623393a9c";
      web-artifacts-builder = "github:anthropics/skills/skills/web-artifacts-builder@b0cbd3df1533b396d281a6886d5132f623393a9c";
      uv = "github:wshobson/agents/plugins/python-development/skills/uv-package-manager@a6f0f457c4e41cbb0ad329b691d28e255a829210";
      rust-best-practices = "github:apollographql/skills/skills/rust-best-practices@5dca44919c9a320d5c0cec70ed5107d4d7a6a816";
      vitepress = "github:antfu/skills/skills/vitepress@c35a5588a5158b5b404a14fb10469b2b6dc1952b";
    };
  };
}
