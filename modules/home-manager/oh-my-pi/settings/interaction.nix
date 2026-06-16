# Interaction settings: conversation flow, input/startup, notifications, STT.
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

  doubleEscapeAction = mkOpt (t.enum [
    "branch"
    "tree"
    "none"
  ]) "Action when pressing Escape twice with an empty editor.";
  treeFilterMode = mkOpt (t.enum [
    "default"
    "no-tools"
    "user-only"
    "labeled-only"
    "all"
  ]) "Default filter mode when opening the session tree.";
  autocompleteMaxVisible = mkOpt num "Max visible items in the autocomplete dropdown (3-20).";
  emojiAutocomplete = mkOpt t.bool "Suggest emojis from :name: shortcodes and expand text emoticons.";
  collapseChangelog = mkOpt t.bool "Show condensed changelog after updates.";

  loop = mkSection "/loop iteration behaviour." {
    mode = mkOpt (t.enum [
      "prompt"
      "compact"
      "reset"
    ]) "What happens between /loop iterations before re-submitting the prompt.";
  };

  startup = mkSection "Startup behaviour." {
    quiet = mkOpt t.bool "Skip welcome screen and startup status messages.";
    setupWizard = mkOpt t.bool "Show newly added onboarding steps once per setup version.";
    checkUpdate = mkOpt t.bool "If false, skip the update check.";
  };

  completion = mkSection "Completion notifications." {
    notify = mkOpt onOff "Notify when the agent completes.";
  };

  ask = mkSection "Ask tool behaviour." {
    timeout = mkOpt num "Auto-select recommended option after timeout in seconds (0 to disable).";
    notify = mkOpt onOff "Notify when the ask tool is waiting for input.";
  };

  stt = mkSection "Speech-to-text input." {
    enabled = mkOpt t.bool "Enable speech-to-text input via microphone.";
    language = mkOpt t.str "Spoken language code (default: en).";
    modelName = mkOpt (t.enum [
      "fast"
      "balanced"
      "turbo"
      "parakeet"
    ]) "Speech-to-text model.";
  };

  magicKeywords = mkSection "Magic keyword triggers in user input." {
    enabled = mkOpt t.bool "Enable magic-keyword detection.";
    ultrathink = mkOpt t.bool "`ultrathink` keyword bumps the thinking level.";
    orchestrate = mkOpt t.bool "`orchestrate`/`parallel` keyword encourages subagent fan-out.";
    workflow = mkOpt t.bool "Enable workflow magic keywords.";
  };

  paste = mkSection "Paste handling." {
    largeMenuThreshold = mkOpt num "Pasted line count above which the large-paste menu appears.";
  };

  collab = mkSection "Realtime collaboration relay." {
    relayUrl = mkOpt t.str "Collab relay server URL.";
    displayName = mkOpt t.str "Display name shown to other collaborators.";
  };

  share = mkSection "Session sharing." {
    serverUrl = mkOpt t.str "Share server URL.";
    redactSecrets = mkOpt t.bool "Redact secrets before sharing a session.";
  };

  features = mkSection "Experimental feature flags." {
    unexpectedStopDetection = mkOpt t.bool "Use a small model to detect when the assistant says it will continue but stops without tool calls, and auto-prompt it to continue.";
  };
}
