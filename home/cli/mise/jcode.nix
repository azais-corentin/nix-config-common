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
      default_model = "claude-opus-5";
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
      pdf = "github:anthropics/skills/skills/pdf@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      pptx = "github:anthropics/skills/skills/pptx@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      frontend-design = "github:anthropics/skills/skills/frontend-design@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      web-artifacts-builder = "github:anthropics/skills/skills/web-artifacts-builder@41bbe19d1a1a7eaab5e7bb9050a417e5c6cffc8f";
      uv = "github:wshobson/agents/plugins/python-development/skills/uv-package-manager@a30778f8c4e6b0a87567941b7cca4f534bf642b6";
      rust-best-practices = "github:apollographql/skills/skills/rust-best-practices@c288eb80629dd2309eed81f23d693f66a452d043";
      vitepress = "github:antfu/skills/skills/vitepress@a74f281a27dadc02397bc1a174b0f2c97531b6ae";
    };
  };
}
