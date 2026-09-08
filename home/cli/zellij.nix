{
  programs.zellij = {
    enable = true;
    enableBashIntegration = false;
    enableFishIntegration = false;
    enableZshIntegration = false;
    settings = {
      default_layout = "default";
      simplified_ui = false;
      pane_frames = true;
      pane_frame_style = "full";
      mouse_mode = true;
      show_startup_tips = true;
      on_force_close = "detach";
      session_serialization = true;
      serialize_pane_viewport = false;
    };
    extraConfig = builtins.readFile ./zellij-unlock-first.kdl;
  };
}
