# Appearance settings: theme, status line, terminal/images, tui, display, plus
# the top-level appearance scalars.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection;
  t = lib.types;

  statusLineSegments = [
    "pi"
    "model"
    "mode"
    "path"
    "git"
    "pr"
    "subagents"
    "token_in"
    "token_out"
    "token_total"
    "token_rate"
    "cost"
    "context_pct"
    "context_total"
    "time_spent"
    "time"
    "session"
    "hostname"
    "cache_read"
    "cache_write"
    "cache_hit"
    "session_name"
    "usage"
  ];
in
{
  symbolPreset = mkOpt (t.enum [
    "unicode"
    "nerd"
    "ascii"
  ]) "Icon/symbol style.";
  colorBlindMode = mkOpt t.bool "Use blue instead of green for diff additions.";
  showHardwareCursor = mkOpt t.bool "Show terminal cursor for IME support.";

  theme = mkSection "Theme selection." {
    dark = mkOpt t.str "Theme used when terminal has a dark background.";
    light = mkOpt t.str "Theme used when terminal has a light background.";
  };

  statusLine = mkSection "Status line configuration." {
    preset = mkOpt (t.enum [
      "default"
      "minimal"
      "compact"
      "full"
      "nerd"
      "ascii"
      "custom"
    ]) "Pre-built status line configuration.";
    separator = mkOpt (t.enum [
      "powerline"
      "powerline-thin"
      "slash"
      "pipe"
      "block"
      "none"
      "ascii"
    ]) "Style of separators between segments.";
    sessionAccent = mkOpt t.bool "Use the session name color for the editor border and status line gap.";
    showHookStatus = mkOpt t.bool "Display hook status messages below status line.";
    leftSegments = mkOpt (t.listOf (t.enum statusLineSegments)) "Custom-preset left segments.";
    rightSegments = mkOpt (t.listOf (t.enum statusLineSegments)) "Custom-preset right segments.";
    segmentOptions = mkOpt (t.attrsOf helpers.yamlFormat.type) "Per-segment options keyed by segment id.";
    transparent = mkOpt t.bool "Use a transparent status line background.";
  };

  terminal = mkSection "Terminal rendering." {
    showImages = mkOpt t.bool "Render images inline in terminal.";
  };

  images = mkSection "Image handling." {
    autoResize = mkOpt t.bool "Resize large images to 2000x2000 max for better model compatibility.";
    blockImages = mkOpt t.bool "Prevent images from being sent to LLM providers.";
    describeForTextModels = mkOpt t.bool "For non-vision models, save attached images under local:// and inject a vision-model description instead of dropping them.";
  };

  tui = mkSection "TUI image/hyperlink limits." {
    maxInlineImageColumns = mkOpt helpers.num "Maximum width in terminal columns for inline images (0 = unlimited).";
    maxInlineImageRows = mkOpt helpers.num "Maximum height in terminal rows for inline images (0 = viewport-based).";
    maxInlineImages = mkOpt helpers.num "Maximum inline images kept as live terminal graphics (0 = unlimited).";
    textSizing = mkOpt t.bool "Render Markdown H1 headings at 2x scale via Kitty's OSC 66 (Kitty terminals only).";
    hyperlinks = mkOpt (t.enum [
      "off"
      "auto"
      "always"
    ]) "Wrap file paths in OSC 8 hyperlinks (auto/off/always).";
    tight = mkOpt t.bool "Remove the 1-column horizontal padding from the left/right of terminal output.";
  };

  display = mkSection "Display rendering." {
    cacheMissMarker = mkOpt t.bool "Show a divider above an assistant turn whose request missed the prompt cache.";
    shimmer = mkOpt (t.enum [
      "classic"
      "kitt"
      "disabled"
    ]) "Animation style for working/loading messages.";
    showTokenUsage = mkOpt t.bool "Show per-turn token usage on assistant messages.";
    smoothStreaming = mkOpt t.bool "Reveal assistant text smoothly while streamed chunks arrive.";
  };
}
