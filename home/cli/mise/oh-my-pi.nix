# Shared oh-my-pi base: the intersection of both consumers' settings. The
# module namespace is top-level `oh-my-pi.*` (declared in
# modules/home-manager/oh-my-pi). Consumers add their own secrets, providers,
# and memory backend in a per-repo layer.
{ ... }:
{
  programs.mise.globalConfig.tools."github:can1357/oh-my-pi".version = "latest";
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "github:can1357/oh-my-pi" ];

  oh-my-pi = {
    enable = true;

    settings = {
      providers = {
        webSearch = "auto";
        tinyModel = "online";
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
      images = {
        autoResize = true;
        blockImages = false;
      };
      tui.hyperlinks = "auto";
      tui.tight = true;
      display = {
        shimmer = "kitt";
        showTokenUsage = false;
      };
      startup = {
        setupWizard = false;
        showSplash = false;
      };
      task.showResolvedModelBadge = false;
      task.isolation.mode = "auto";
      task.isolation.merge = "branch";
      task.disabledAgents = [
        "explore"
        "oracle"
        "librarian"
      ];
      edit.mode = "hashline";
      loop.mode = "reset";
      github.enabled = true;
      tools.discoveryMode = "mcp-only";
      mcp.discoveryMode = true;
      modelRoles = {
        default = "anthropic/claude-opus-4-8";
        smol = "anthropic/claude-haiku-4-5";
        slow = "anthropic/claude-opus-4-8";
        vision = "anthropic/claude-opus-4-8";
        plan = "anthropic/claude-opus-4-8";
        designer = "anthropic/claude-opus-4-8";
        commit = "anthropic/claude-sonnet-4-6";
        task = "anthropic/claude-sonnet-4-6";
      };
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
