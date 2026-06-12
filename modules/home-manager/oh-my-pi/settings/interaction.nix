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
      "tiny"
      "tiny.en"
      "base"
      "base.en"
      "small"
      "small.en"
      "medium"
      "medium.en"
      "large"
    ]) "Whisper model size.";
  };
}
