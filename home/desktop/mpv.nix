{ pkgs, ... }:
{
  programs.mpv = {
    enable = true;
    package = (
      pkgs.mpv.override {
        scripts = with pkgs.mpvScripts; [
          uosc
          sponsorblock
        ];

        mpv-unwrapped = pkgs.mpv-unwrapped.override {
          waylandSupport = true;
        };
      }
    );
    config = {
      hwdec = "auto-safe";
      vo = "gpu-next";
      profile = "high-quality";
      ytdl-format = "bestvideo+bestaudio";
      drag-and-drop = "replace";
      cache = "yes";
    };
    bindings.r = "cycle-values video-rotate 90 180 270 0";
    profiles.mpi = {
      # Disable audio entirely
      audio = false;
      mute = true;

      # Disable subtitle loading
      sid = "no";
      sub-auto = "no";

      # Disable OSD/OSC/UI chrome
      osc = false;
      osd-level = 0;
      term-status-msg = " ";
      really-quiet = true;

      # Don't load scripts (console, stats, etc.)
      load-scripts = false;
      load-console = false;
      load-stats-overlay = false;
      load-select = false;
      load-context-menu = false;

      # Don't autoload external files
      autoload-files = false;
      audio-file-auto = "no";
      cover-art-auto = "no";

      # Don't resume or save state
      resume-playback = false;
      save-position-on-quit = false;

      # Disable ytdl
      ytdl = false;

      # Image behavior
      image-display-duration = "inf";
      loop-file = "inf";
      loop-playlist = "inf";
      reset-on-next-file = "video-pan-x,video-pan-y,video-zoom";

      # Simpler rendering
      deband = false;
      interpolation = false;
      correct-downscaling = false;
      linear-downscaling = false;
      sigmoid-upscaling = false;
      scale = "bilinear";
      dscale = "bilinear";
      cscale = "bilinear";

      # Reduce demuxer/cache overhead
      cache = false;
      demuxer-readahead-secs = 0;
      demuxer-max-bytes = "1MiB";

      # Window
      force-window = true;
      auto-window-resize = true;
      keepaspect = true;
      title = "\${media-title} - mvi";
    };
  };

  home.shellAliases.mpi = "mpv --profile=mpi";
}
