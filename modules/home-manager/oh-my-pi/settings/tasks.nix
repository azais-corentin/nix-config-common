# Tasks settings: plan/goal modes, task delegation + isolation, todo auto-clear,
# skill/command discovery toggles.
#
# Note: settings.skills here are the config.yml skill-discovery toggles, distinct
# from the oh-my-pi.skills option that installs skill files.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;
in
{
  plan = mkSection "Plan mode." {
    enabled = mkOpt t.bool "Enable plan mode for read-only exploration before execution.";
    defaultOnStartup = mkOpt t.bool "Enter plan mode by default on startup.";
  };

  goal = mkSection "Goal mode." {
    enabled = mkOpt t.bool "Enable per-session goal mode and the hidden goal tool.";
    statusInFooter = mkOpt t.bool "Show token budget alongside the goal indicator in the status line.";
    continuationModes = mkOpt (t.listOf t.str) "Run modes where active goals may auto-continue between turns.";
  };

  task = mkSection "Subagent delegation and isolation." {
    isolation = mkSection "Subagent filesystem isolation." {
      mode = mkOpt (t.enum [
        "none"
        "auto"
        "apfs"
        "btrfs"
        "zfs"
        "reflink"
        "overlayfs"
        "projfs"
        "block-clone"
        "rcopy"
      ]) "Isolation backend for subagents.";
      merge = mkOpt (t.enum [
        "patch"
        "branch"
      ]) "How isolated task changes are integrated.";
      commits = mkOpt (t.enum [
        "generic"
        "ai"
      ]) "Commit message style for nested repo changes.";
    };
    eager = mkOpt (t.enum [
      "default"
      "preferred"
      "always"
    ]) "How eagerly to delegate work to subagents.";
    batch = mkOpt t.bool "Allow the task tool to spawn multiple subagents in one batched call.";
    maxConcurrency = mkOpt num "Concurrent limit for subagents (0 = unlimited).";
    enableLsp = mkOpt t.bool "Allow subagents spawned via the task tool to use the lsp tool.";
    maxRecursionDepth = mkOpt num "How many levels deep subagents can spawn their own subagents (-1 = unlimited).";
    maxRuntimeMs = mkOpt num "Hard wall-clock limit per subagent in ms (0 disables).";
    agentIdleTtlMs = mkOpt num "How long an idle subagent stays live before parking to disk, in ms (0 = until exit).";
    softRequestBudget = mkOpt num "Soft per-subagent request budget; crossing it injects a wrap-up notice, 1.5x aborts gracefully (0 disables).";
    disabledAgents = mkOpt (t.listOf t.str) "Agent ids that cannot be spawned.";
    agentModelOverrides = mkOpt (t.attrsOf t.str) "Per-agent model overrides.";
    showResolvedModelBadge = mkOpt t.bool "Display the actual model id used by each subagent in the task widget.";
  };

  tasks = mkSection "Todo list lifecycle." {
    todoClearDelay = mkOpt num "Seconds before removing completed/abandoned tasks from the list (-1 = never).";
  };

  skills = mkSection "Skill discovery toggles (config.yml)." {
    enabled = mkOpt t.bool "Enable the skills subsystem.";
    enableSkillCommands = mkOpt t.bool "Register skills as /skill:name commands.";
    enableCodexUser = mkOpt t.bool "Load Codex user skills.";
    enableClaudeUser = mkOpt t.bool "Load Claude user skills.";
    enableClaudeProject = mkOpt t.bool "Load Claude project skills.";
    enablePiUser = mkOpt t.bool "Load pi user skills.";
    enablePiProject = mkOpt t.bool "Load pi project skills.";
    enableAgentsUser = mkOpt t.bool "Load skills from ~/.agents/.";
    enableAgentsProject = mkOpt t.bool "Load skills from .agents/.";
    customDirectories = mkOpt (t.listOf t.str) "Additional skill directories to scan.";
    ignoredSkills = mkOpt (t.listOf t.str) "Skill names to ignore.";
    includeSkills = mkOpt (t.listOf t.str) "Skill names to force-include.";
  };

  commands = mkSection "External command discovery toggles." {
    enableClaudeUser = mkOpt t.bool "Load commands from ~/.claude/commands/.";
    enableClaudeProject = mkOpt t.bool "Load commands from .claude/commands/.";
    enableOpencodeUser = mkOpt t.bool "Load commands from ~/.config/opencode/commands/.";
    enableOpencodeProject = mkOpt t.bool "Load commands from .opencode/commands/.";
  };
}
