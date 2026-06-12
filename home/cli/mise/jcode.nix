{ config, ... }:
{
  # 1. mise tool entry — github backend, autodetects linux-x86_64 / linux-aarch64 tarballs.
  programs.mise.globalConfig.tools."github:1jehuang/jcode" = {
    version = "latest";
    rename_exe = "jcode"; # rename the extracted wrapper → "jcode"
    filter_bins = "jcode"; # only symlink `jcode` onto PATH (hide the .bin)
  };

  # 2. MCP — reuse the same JSON the programs.mcp module already generates.
  home.file.".jcode/mcp.json".source = config.xdg.configFile."mcp/mcp.json".source;

  # 3. Declarative config + skills via the jcode HM module.
  jcode = {
    enable = true;

    features = {
      memory = true;
      swarm = false;
    };

    display = {
      centered = false;
      show_thinking = true;
      performance = "full";
    };

    provider = {
      default_provider = "claude";
      default_model = "claude-opus-4-8";
      openai_reasoning_effort = "medium";
      anthropic_reasoning_effort = "high";
    };

    agents = {
      memory_sidecar_enabled = true;
      swarm_spawn_mode = "auto";
    };

    tools = {
      profile = "full";
      enabled = [ "lsp" ];
    };

    gateway = {
      enabled = true;
      port = 7643;
      bind_addr = "0.0.0.0";
    };

    safety = {
      desktop_notifications = true;
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
