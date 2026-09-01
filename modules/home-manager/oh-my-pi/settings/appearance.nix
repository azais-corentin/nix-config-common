# Appearance settings: theme, composer, status line, terminal/images, tui,
# display, plus the top-level appearance scalars.
#
# `images` also carries the model-tab `images.urls.*` blob-serving keys: top-level
# config.yml keys must stay disjoint across settings/*.nix, and `images` lives here.
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
    "collab"
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

  composer = mkSection "Input composer layout." {
    shape = mkOpt t.str "Visual layout of the input editor and status line. Upstream types this as a free string because extensions register shapes at runtime; the built-ins are band (default), box, claude, pi, borderless, rule, field and rail.";
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
    compactThinkingLevel = mkOpt t.bool "Show the thinking level as a single icon on the model name instead of a separate suffix.";
    contextLine =
      mkOpt
        (t.enum [
          "off"
          "percentage"
          "annotated"
          "embedded"
        ])
        "How the line between the left and right segments reflects context usage (box composer shape only).";
  };

  terminal = mkSection "Terminal rendering." {
    showImages = mkOpt t.bool "Render images inline in terminal.";
    showProgress = mkOpt t.bool "Emit OSC 9;4 indeterminate terminal progress while the agent or context maintenance runs.";
  };

  images = mkSection "Image handling." {
    autoResize = mkOpt t.bool "Resize large images to 2000x2000 max for better model compatibility.";
    blockImages = mkOpt t.bool "Prevent images from being sent to LLM providers.";
    describeForTextModels = mkOpt t.bool "For non-vision models, save attached images under local:// and inject a vision-model description instead of dropping them.";
    urls = mkSection "Serve outgoing images as URLs instead of inline base64." {
      enabled = mkOpt t.bool "Publish outgoing images through the backend chain and send URL-fetching providers short URLs instead of inline base64 (falls back to inline when every backend or a provider fetch fails).";
      backends = mkOpt (t.listOf t.str) "Ordered blob-destination ids tried when publishing images (default: provider-files, tailscale, cloudflared, litterbox). Not enumerated here because the valid set is filtered at runtime.";
      bindHost = mkOpt t.str "Host the blob server binds to; loopback for tunnels, 0.0.0.0 for direct serving.";
      command = mkOpt t.str "Argv template for the command backend; {file} is the image path, {mime}/{ext} optional. The last URL printed on stdout is used.";
      publicBaseUrl = mkOpt t.str "Externally reachable base URL fronting the blob server (required for ssh, optional for direct).";
      sshTarget = mkOpt t.str "user@host destination for the ssh reverse forward.";
      sshRemotePort = mkOpt helpers.num "Remote listen port of the ssh reverse forward that your web server proxies to.";
      ttlHours = mkOpt helpers.num "Serving window in hours for locally hosted image URLs, measured from the last send (0 keeps links alive while the broker runs).";
      options = mkOpt (t.attrsOf helpers.yamlFormat.type) "Per-backend options keyed by blob-destination id.";
      credentials = mkOpt (t.attrsOf (t.attrsOf t.str)) "Per-backend credentials keyed by blob-destination id. Upstream flags these as credentials: values set here land in world-readable Nix store output, so keep real secrets in the consumer's sops layer and out of this option.";
    };
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
    renderMermaid = mkOpt t.bool "Render Mermaid fenced code blocks as ASCII diagrams.";
    codexResetFireworks = mkOpt t.bool "Celebrate unscheduled Codex weekly usage resets and newly banked saved resets with a fireworks overlay that remains until Escape.";
    resizeScrollback =
      mkOpt
        (t.enum [
          "append"
          "rebuild"
          "preserve"
        ])
        "How a settled terminal resize refreshes transcript rows retained in terminal scrollback (append replays below history, rebuild erases and replays, preserve repaints only the viewport).";
    imeSafeCursor = mkOpt t.bool "Move the prompt's bottom border to a separate row so macOS IME preedit cannot displace it.";
    titleState = mkOpt t.bool "Show the agent run state in the terminal title separator (spinner/>/!).";
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
    collapseCompacted = mkOpt t.bool "Collapse pre-compaction history behind the summary divider on the live transcript (disable to keep the full transcript inline).";
    hideToolActivity = mkOpt t.bool "Hide model-initiated tool calls and results from the transcript.";
    showTurnTime = mkOpt t.bool "Show the total prompt-to-yield time (including tool calls) on assistant message usage rows.";
  };
}
