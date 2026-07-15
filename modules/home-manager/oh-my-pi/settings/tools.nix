# Tools settings: tool output/approval, every optional tool toggle, async jobs,
# MCP runtime behaviour, plus the todo and dev/autoqa groups. All option names
# here map 1:1 onto flat schema keys (v17 flattened the former todo.reminders.max
# and dev.autoqa.consent collisions into todo.remindersMax / dev.autoqaConsent).
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
    xdev = mkOpt t.bool "Mount rarely-used (discoverable) tools under xd:// device URLs driven via read/write instead of shipping their schemas on every request (disable to expose every enabled tool top-level).";
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
    remindersMax = mkOpt num "Maximum reminders to complete todos before giving up.";
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

  irc = mkSection "Agent-to-agent messaging (hub)." {
    timeoutMs = mkOpt num "Default timeout for hub message waits (and send await:true) in ms (0 disables).";
  };

  debug = mkSection "Debug tool." {
    enabled = mkOpt t.bool "Enable the debug tool for DAP-based debugging.";
  };

  launch = mkSection "Launch tool." {
    enabled = mkOpt t.bool "Enable the launch tool for supervising shared long-running project processes.";
  };

  generate_image = mkSection "Image generation tool." {
    enabled = mkOpt t.bool "Enable the generate_image tool for text-to-image generation and editing (exposed as an xd:// device when tools.xdev is on).";
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
    ]) "How long a hub wait watches background jobs before returning the current state.";
  };

  mcp = mkSection "MCP runtime behaviour (server definitions live in mcp.json, not here)." {
    enableProjectConfig = mkOpt t.bool "Load .mcp.json/mcp.json from the project root.";
    notifications = mkOpt t.bool "Inject MCP resource updates into the agent conversation.";
    notificationDebounceMs = mkOpt num "Debounce window for MCP resource update notifications.";
  };

  dev = mkSection "Developer / auto-QA options." {
    autoqa = mkOpt t.bool "Enable automated tool issue reporting (report_tool_issue) for all agents.";
    autoqaConsent = mkOpt (t.enum [
      "unset"
      "granted"
      "denied"
    ]) "Consent for sharing automatic grievances.";
    autoqaPush = mkSection "Auto-QA grievance push target." {
      endpoint = mkOpt t.str "Full URL that receives the JSON payload.";
      token = mkOpt t.str "Bearer token for the push endpoint.";
    };
  };
}
