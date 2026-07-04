# Tools settings: tool output/approval, every optional tool toggle, async jobs,
# MCP runtime behaviour, plus the todo and dev/autoqa groups (both of which have
# the nested boolean-vs-subkey collision resolved at render time in settings.nix).
#
# Collision option names exposed here (not raw schema keys):
#   todo.reminders + todo.reminderMax  → rendered as todo.reminders (bool | { max }).
#   dev.autoqa     + dev.autoqaConsent → rendered as dev.autoqa     (bool | { consent }).
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;
in
{
  tools = mkSection "Tool output, approval, discovery and execution limits." {
    artifactSpillThreshold = mkOpt num "Tool output above this size (KB) is saved as an artifact.";
    artifactTailBytes = mkOpt num "Tail content (KB) kept inline when output spills to an artifact.";
    artifactHeadBytes = mkOpt num "Head content (KB) kept inline alongside the tail (0 = tail-only).";
    outputMaxColumns = mkOpt num "Per-line byte cap for streaming tool outputs and read (0 disables).";
    artifactTailLines = mkOpt num "Maximum lines of tail content kept inline when output spills.";
    approval = mkOpt (t.attrsOf (
      t.enum [
        "allow"
        "prompt"
        "deny"
      ]
    )) "Per-tool approval policies (allow/prompt/deny).";
    approvalMode = mkOpt (t.enum [
      "always-ask"
      "write"
      "yolo"
    ]) "Default approval behaviour for tool calls.";
    intentTracing = mkOpt t.bool "Ask the agent to describe the intent of each tool call before executing it.";
    maxTimeout = mkOpt num "Maximum timeout in seconds the agent can set for any tool (0 = no limit).";
    discoveryMode = mkOpt (t.enum [
      "auto"
      "off"
      "mcp-only"
      "all"
    ]) "Hide tools behind a search tool to save tokens.";
    essentialOverride = mkOpt (t.listOf t.str) "Override the always-loaded built-in tools.";
    abortOnFabricatedResult = mkOpt t.bool "Abort the turn when a fabricated tool result is detected.";
    format = mkOpt (t.enum [
      "auto"
      "native"
      "glm"
      "hermes"
      "kimi"
      "xml"
      "anthropic"
      "deepseek"
      "harmony"
      "qwen3"
      "gemini"
      "gemma"
      "minimax"
    ]) "Tool-calling dialect exposed to the model.";
  };

  todo = mkSection "Todo tool." {
    enabled = mkOpt t.bool "Enable the todo_write tool for task tracking.";
    reminders = mkOpt t.bool "Remind the agent to complete todos before stopping.";
    reminderMax = mkOpt num "Maximum reminders to complete todos before giving up (sets todo.reminders.max).";
    eager = mkOpt (t.enum [
      "default"
      "preferred"
      "always"
    ]) "How eagerly to auto-create a comprehensive todo list.";
  };

  glob = mkSection "Glob tool." {
    enabled = mkOpt t.bool "Enable the glob tool for glob-based file lookup.";
  };

  grep = mkSection "Grep tool." {
    enabled = mkOpt t.bool "Enable the grep tool for regex content search.";
    contextBefore = mkOpt num "Lines of context before each grep match.";
    contextAfter = mkOpt num "Lines of context after each grep match.";
  };

  astGrep = mkSection "AST grep tool." {
    enabled = mkOpt t.bool "Enable the ast_grep tool for structural AST search.";
  };

  astEdit = mkSection "AST edit tool." {
    enabled = mkOpt t.bool "Enable the ast_edit tool for structural AST rewrites.";
  };

  irc = mkSection "Agent-to-agent IRC messaging." {
    timeoutMs = mkOpt num "Drop IRC messages whose recipient does not respond within this many ms (0 disables).";
  };

  debug = mkSection "Debug tool." {
    enabled = mkOpt t.bool "Enable the debug tool for DAP-based debugging.";
  };

  speechgen = mkSection "Speech generation tool." {
    enabled = mkOpt t.bool "Enable the tts tool for on-device (Kokoro) or xAI Grok Voice speech-file synthesis.";
  };

  inspect_image = mkSection "Inspect image tool." {
    enabled = mkOpt t.bool "Enable the inspect_image tool, delegating to a vision-capable model.";
  };

  checkpoint = mkSection "Checkpoint/rewind tools." {
    enabled = mkOpt t.bool "Enable the checkpoint and rewind tools for context checkpointing.";
  };

  fetch = mkSection "URL fetching." {
    enabled = mkOpt t.bool "Allow the read tool to fetch and process URLs.";
  };

  vault = mkSection "Obsidian vault access." {
    enabled = mkOpt t.bool "Enable the vault:// internal URL for reading/editing Obsidian vault content.";
  };

  github = mkSection "GitHub tool." {
    enabled = mkOpt t.bool "Enable the github tool (op-based repository/issue/PR dispatch).";
    cache = mkSection "GitHub view cache." {
      enabled = mkOpt t.bool "Cache rendered issue/PR view output so repeated reads are free.";
      softTtlSec = mkOpt num "Within this window, cached rows are returned directly.";
      hardTtlSec = mkOpt num "Past soft TTL but within hard TTL, refresh in background; past hard TTL, drop.";
    };
  };

  web_search = mkSection "Web search tool." {
    enabled = mkOpt t.bool "Enable the web_search tool for web searching.";
  };

  browser = mkSection "Browser tool." {
    enabled = mkOpt t.bool "Enable the browser tool.";
    headless = mkOpt t.bool "Launch the browser in headless mode.";
    screenshotDir = mkOpt t.str "Directory to save screenshots (supports ~).";
    cmux = mkOpt t.bool "Use cmux for browser sessions.";
  };

  async = mkSection "Async background jobs." {
    enabled = mkOpt t.bool "Enable async bash commands and background task execution.";
    maxJobs = mkOpt num "Maximum concurrent background jobs.";
    pollWaitDuration = mkOpt (t.enum [
      "5s"
      "10s"
      "30s"
      "1m"
      "5m"
      "smart"
    ]) "How long the poll tool waits for background job updates before returning.";
  };

  mcp = mkSection "MCP runtime behaviour (server definitions live in mcp.json, not here)." {
    enableProjectConfig = mkOpt t.bool "Load .mcp.json/mcp.json from the project root.";
    discoveryMode = mkOpt t.bool "Hide MCP tools by default and expose them through a discovery tool.";
    discoveryDefaultServers = mkOpt (t.listOf t.str) "Servers kept visible while discovery mode hides other MCP tools.";
    notifications = mkOpt t.bool "Inject MCP resource updates into the agent conversation.";
    notificationDebounceMs = mkOpt num "Debounce window for MCP resource update notifications.";
  };

  dev = mkSection "Developer / auto-QA options." {
    autoqa = mkOpt t.bool "Enable automated tool issue reporting (report_tool_issue) for all agents.";
    autoqaConsent = mkOpt (t.enum [
      "unset"
      "granted"
      "denied"
    ]) "Consent for sharing automatic grievances (sets dev.autoqa.consent).";
    autoqaPush = mkSection "Auto-QA grievance push target." {
      endpoint = mkOpt t.str "Full URL that receives the JSON payload.";
      token = mkOpt t.str "Bearer token for the push endpoint.";
    };
  };
}
