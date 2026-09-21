# Interaction settings: conversation flow, input/spelling, startup/update,
# notifications, STT.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;

  flowMode = t.enum [
    "all"
    "one-at-a-time"
  ];
  onOff = t.enum [
    "on"
    "off"
  ];
in
{
  steeringMode = mkOpt flowMode "How to process queued messages while the agent is working.";
  followUpMode = mkOpt flowMode "How to drain follow-up messages after a turn completes.";
  interruptMode = mkOpt (t.enum [
    "immediate"
    "wait"
  ]) "When steering messages interrupt tool execution.";

  doubleEscapeAction =
    mkOpt
      (t.enum [
        "rewind"
        "none"
      ])
      "Action when pressing Escape twice with an empty editor (rewind opens the transcript rewind selector).";
  treeFilterMode = mkOpt (t.enum [
    "default"
    "no-tools"
    "user-only"
    "labeled-only"
    "all"
  ]) "Default filter mode when opening the session tree.";
  autocompleteMaxVisible = mkOpt num "Max visible items in the autocomplete dropdown (3-20).";
  emojiAutocomplete = mkOpt t.bool "Suggest emojis from :name: shortcodes and expand text emoticons.";

  loop = mkSection "/loop iteration behaviour." {
    mode = mkOpt (t.enum [
      "prompt"
      "compact"
      "reset"
    ]) "What happens between /loop iterations before re-submitting the prompt.";
    conditionTimeoutMs = mkOpt num "Max wait for a /loop --while|--until condition command before treating it as broken and stopping the loop (0 = wait indefinitely).";
  };

  spelling = mkSection "macOS dictionary integration for the prompt editor." {
    autocomplete = mkOpt t.bool "Show macOS dictionary word completions as inline hints accepted with Tab.";
    autocorrect = mkOpt t.bool "Apply confident macOS spelling corrections after completed words.";
    typoDetection = mkOpt t.bool "Mark misspelled prompt words with the active macOS dictionaries.";
  };

  startup = mkSection "Startup behaviour." {
    quiet = mkOpt t.bool "Skip welcome screen and startup status messages.";
    setupWizard = mkOpt t.bool "Show newly added onboarding steps once per setup version.";
    checkUpdate = mkOpt t.bool "If false, skip the update check.";
    showSplash = mkOpt t.bool "Show the animated setup splash on normal interactive startup (quiet still suppresses it).";
    changelogMode =
      mkOpt
        (t.enum [
          "summary"
          "expanded"
          "hidden"
        ])
        "Whether update notes start as a summary, full details, or stay hidden. Successor to the removed collapseChangelog.";
  };

  update = mkSection "Update channel." {
    channel = mkOpt (t.enum [
      "stable"
      "canary"
    ]) "Update channel used by `omp update` and the startup update check.";
  };

  completion = mkSection "Completion notifications." {
    notify = mkOpt onOff "Notify when the agent completes.";
  };

  error = mkSection "Error notifications." {
    notify = mkOpt onOff "Notify when the agent stops with an error.";
  };

  ask = mkSection "Ask tool behaviour." {
    enabled = mkOpt t.bool "Enable the ask tool for interactive user questions.";
    timeout = mkOpt num "Auto-select recommended option after timeout in seconds (0 to disable).";
    notify = mkOpt onOff "Notify when the ask tool is waiting for input.";
  };

  stt = mkSection "Speech-to-text input." {
    enabled = mkOpt t.bool "Enable speech-to-text input via microphone.";
    language = mkOpt t.str "Spoken language code (default: en).";
    submitTrigger = mkOpt (t.enum [
      "never"
      "release"
      "release-complete"
      "say-submit"
    ]) "When speech dictation auto-submits.";
  };

  magicKeywords = mkSection "Magic keyword triggers in user input." {
    enabled = mkOpt t.bool "Enable magic-keyword detection.";
    ultrathink = mkOpt t.bool "Let standalone `ultrathink` request maximum automatic thinking and append its hidden notice.";
    orchestrate = mkOpt t.bool "Let standalone `orchestrate` append its hidden multi-agent orchestration notice.";
    workflow = mkOpt t.bool "Let standalone `workflowz` append its hidden eval workflow notice.";
    jevify = mkOpt t.bool "Let standalone `jevify` append its hidden bulk-judge classification notice.";
  };

  paste = mkSection "Paste handling." {
    largeMenuThreshold = mkOpt num "Pasted line count above which the large-paste menu appears.";
  };

  collab = mkSection "Realtime collaboration relay." {
    relayUrl = mkOpt t.str "Collab relay server URL.";
    displayName = mkOpt t.str "Display name shown to other collaborators.";
    webUrl = mkOpt t.str "Browser UI for /collab links; empty derives from relayUrl (explicit http:// is localhost-only).";
    autoStart =
      mkOpt
        (t.enum [
          "off"
          "view"
          "control"
        ])
        "Host every interactive session via collab.relayUrl as it starts and publish it to the local registry; view hands out view-only links, control hands out links that can prompt the session.";
  };

  share = mkSection "Session sharing." {
    serverUrl = mkOpt t.str "Share server URL.";
    redactSecrets = mkOpt t.bool "Redact secrets before sharing a session.";
    store = mkOpt (t.enum [
      "blob"
      "gist"
    ]) "Where /share uploads the encrypted session blob.";
  };

  stream = mkSection "Live session streaming (omp stream)." {
    serverUrl = mkOpt t.str "Live stream server used by `omp stream` (https://host[:port]); viewers watch at <base>/<your Stencil username>.";
    redactPatterns = mkOpt (t.listOf t.str) "Additional regular expressions redacted from every streamed row, on top of env/secrets.yml values and built-in credential shapes.";
  };

  features = mkSection "Experimental feature flags." {
    unexpectedStopDetection =
      mkOpt
        (t.enum [
          "none"
          "mechanical"
          "smart"
        ])
        "Automatically recover when the assistant stops without a visible message (upstream default: mechanical). Mechanical retries stops with no visible assistant message, excluding tool calls; smart additionally classifies text-only stops with a small model.";
  };

  recap = mkSection "Idle recap." {
    enabled = mkOpt t.bool "Generate a brief LLM recap of where things stand after the terminal has been idle.";
    idleSeconds = mkOpt num "Seconds to wait while idle before showing the recap.";
  };

  git = mkSection "Git integration." {
    enabled = mkOpt t.bool "Show git branch/status/PR info in the TUI and watch repo metadata.";
  };
}
