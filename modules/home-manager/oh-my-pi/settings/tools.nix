# Tools settings: tool output/approval, every optional tool toggle, async jobs,
# MCP runtime behaviour, extension handlers, plus the todo, security and
# dev/autoqa groups. All option names here map 1:1 onto flat schema keys (v17
# flattened the former todo.reminders.max and dev.autoqa.consent collisions into
# todo.remindersMax / dev.autoqaConsent).
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
    artifactMaxBytes = mkOpt num "Maximum size in MB of the artifact file saved for streaming tool output (bash, python, js eval); larger output keeps its first 3 MB and the latest remainder (0 = unlimited).";
    approval = mkOpt (t.attrsOf (
      t.enum [
        "allow"
        "prompt"
        "deny"
      ]
    )) "Per-tool approval policies (allow/prompt/deny).";
    approvalMode =
      mkOpt
        (t.enum [
          "always-ask"
          "always-ask-cached"
          "write"
          "yolo"
        ])
        "Default approval behaviour for tool calls: always-ask auto-approves read-only tools; always-ask-cached also asks before file reads and can remember a file or folder; write auto-approves read and workspace-write tools; yolo (upstream default) auto-approves every tier.";
    restrictedFolders = mkOpt (t.listOf t.str) "Folders (supports ~) where every read, write, edit, search or command needs an explicit approval, whatever the approval mode or a remembered grant; commands match by the directory they run in.";
    intentTracing = mkOpt t.bool "Ask the agent to describe the intent of each tool call before executing it.";
    maxTimeout = mkOpt num "Maximum timeout in seconds the agent can set for any tool (0 = no limit).";
    xdev = mkOpt t.bool "Mount rarely-used (discoverable) tools under xd:// device URLs driven via read/write instead of shipping their schemas on every request; sessions granted read but not write get a device-only write transport (only local:// scratch stays writable). Disable to expose every enabled tool top-level.";
    xdevNotices = mkOpt t.bool "Show an `xd://: mounted …` notice when MCP or extension tools are mounted or unmounted; the model still learns of the change with its next prompt.";
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
    xdevDocs =
      mkOpt
        (t.enum [
          "inline"
          "builtins"
          "catalog"
        ])
        "Which mounted-device docs/schemas are inlined in the system prompt (inline = all, builtins = core only, catalog = none).";
    xdevInlineDevices = mkOpt (t.listOf t.str) "When xdevDocs = builtins, glob patterns of dynamic devices to inline anyway.";
    speculativeExecution = mkSection "Experimental speculative execution." {
      enabled = mkOpt t.bool "Run the discard-safe first slice: validated local reads through direct read calls and nested eval (no network, provider completions or live writes).";
      maxInFlight = mkOpt num "Maximum validated local reads allowed to run before normal dispatch.";
    };
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

  find = mkSection "Find tool (semantic grep)." {
    enabled =
      mkOpt
        (t.enum [
          "auto"
          "on"
          "off"
        ])
        "Enable the find tool: natural-language search for files and line ranges, judged by the judge model role. auto (upstream default) enables it only when the judge role resolves to a native TypeSafe jev model.";
  };

  astGrep = mkSection "AST grep tool." {
    enabled = mkOpt t.bool "Enable the ast_grep tool for structural AST search.";
  };

  astEdit = mkSection "AST edit tool." {
    enabled = mkOpt t.bool "Enable the ast_edit tool for structural AST rewrites.";
  };

  debug = mkSection "Debug tool." {
    enabled = mkOpt t.bool "Enable the debug tool for DAP-based debugging.";
  };

  launch = mkSection "Launch tool." {
    enabled = mkOpt t.bool "Enable the launch tool for supervising shared long-running project processes.";
  };

  generate_image = mkSection "Image generation tool." {
    enabled = mkOpt t.bool "Enable the generate_image tool for text-to-image generation and editing (exposed as an xd:// device when tools.xdev is on; upstream default: disabled).";
  };

  speechgen = mkSection "Speech generation tool." {
    enabled = mkOpt t.bool "Enable the tts tool for on-device (Kokoro) or xAI Grok Voice speech-file synthesis.";
  };

  checkpoint = mkSection "Checkpoint/rewind tools." {
    enabled = mkOpt t.bool "Enable the checkpoint and rewind tools for context checkpointing.";
  };

  ida = mkSection "IDA Pro (idalib) integration." {
    enabled = mkOpt t.bool "Open executables read with the read tool in IDA Pro and enable the ida tool; inert when no IDA install is found.";
    installDir = mkOpt t.str "Directory containing libidalib, exported as IDADIR; empty auto-detects ($IDADIR, ida-config.json, standard install paths).";
    python = mkOpt t.str "Python interpreter that can import ida_domain and idapro; empty auto-detects.";
    maxOpen = mkOpt num "Most IDA databases open at once per project; opening another saves and closes the least recently used idle one.";
    idleCloseSec = mkOpt num "Save and close IDA databases idle longer than this many seconds (0 = never); the exec namespace resets on reopen.";
  };

  ratchet = mkSection "Ratchet eval/hillclimb prelude." {
    enabled = mkOpt t.bool "Enable the ratchet eval/hillclimb prelude (/ratchet turns it on for the current session).";
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
    cdpUrl = mkOpt t.str "Default HTTP CDP discovery endpoint (e.g. http://127.0.0.1:9222) to attach to instead of launching a browser; explicit app.cdp_url or app.path on the tool call take precedence.";
    relay = mkOpt t.bool "Drive your own Chrome tabs through the omp browser relay (install the extension once with `omp browser-relay install`). Takes precedence over browser.cdpUrl.";
    relayUrl = mkOpt t.str "omp browser relay endpoint (default http://127.0.0.1:9224).";
    freezeOnTurnEnd = mkOpt t.bool "Freeze OMP-owned headless browser tabs when a turn settles so animated pages stop burning CPU/GPU; tabs unfreeze on next use.";
    idleCloseSec = mkOpt num "Close OMP-owned headless browser tabs idle longer than this many seconds (0 = never); never applies to relay/CDP/spawned browsers.";
    tern = mkOpt t.bool "Inside a Tern pane, open browser tabs as picture-in-pictures over omp's pane instead of headless Chromium (falls back to Chromium when no Tern window can host them; PI_BROWSER_TERN overrides).";
  };

  computer = mkSection "Computer-use tool (native desktop screenshots + input)." {
    enabled = mkOpt t.bool "Enable native host-desktop screenshots and input for OpenAI computer use.";
    display = mkOpt t.str "Capture the active window's display (\"active\"), all displays (\"all\"), or a native display id.";
    maxWidth = mkOpt num "Maximum composite screenshot width in pixels.";
    maxHeight = mkOpt num "Maximum composite screenshot height in pixels.";
    backgroundFallback =
      mkOpt
        (t.enum [
          "takeover"
          "refuse"
        ])
        "What window input does when its background route is unavailable: takeover reruns it in the foreground and returns focus (macOS; elsewhere plain takeover), refuse also keeps the agent from taking the foreground or opening macOS menus.";
  };

  archive = mkSection "Read-only archive eval prelude." {
    enabled = mkOpt t.bool "Expose prompt history, recent projects, past sessions and recaps through the read-only archive eval prelude.";
  };

  async = mkSection "Async background jobs." {
    enabled = mkOpt t.bool "Enable async bash commands and background task execution.";
    maxJobs = mkOpt num "Maximum concurrent background jobs.";
    printWake = mkOpt t.bool "In print mode (-p, --mode json), keep running while this run's background jobs are active and start another turn with each job's result (omp -p --wait-async); off cancels running jobs after the last prompt.";
    widgets = mkOpt t.bool "Draw a live widget per running background job (charts, bars, status grids) in the wait card, jobs pill and jobs sheet, and caption long shell commands; the widget model role (default: smol) writes one spec and at most one caption per job.";
  };

  out = mkSection "Interim replies through out://." {
    enabled = mkOpt t.bool "Let the agent reply mid-task by writing to out://, shown like a response without ending its turn (unset: on in the interactive TUI, off in print, RPC and ACP).";
  };

  mcp = mkSection "MCP runtime behaviour (server definitions live in mcp.json, not here)." {
    enableProjectConfig = mkOpt t.bool "Load .mcp.json/mcp.json from the project root.";
    startupTimeoutMs = mkOpt num "Wait this many milliseconds for initial MCP tool discovery (0 waits until connections settle).";
    notifications = mkOpt t.bool "Inject MCP resource updates into the agent conversation.";
    notificationDebounceMs = mkOpt num "Debounce window for MCP resource update notifications.";
    renderMarkdownResults = mkOpt t.bool "Render non-JSON MCP text results as Markdown in the transcript.";
  };

  extensionHandlers = mkSection "Extension event handlers." {
    toolCallTimeoutMs = mkOpt num "Positive finite active-work timeout in ms for extension tool_call handlers (invalid values fall back to 30000); time awaiting OMP-owned dialogs does not count.";
    modeControl = mkOpt t.bool "Let extensions enter and exit plan, vibe, goal and loop modes via ctx.sessionModes.set(); reading mode state stays available.";
  };

  extensionRenderers = mkSection "Extension renderers." {
    assistantText = mkOpt t.bool "Let extensions change how assistant replies are drawn, redraw a reply in place and receive clicks on their own links; the session, exports and model context keep the reply as written.";
  };

  security = mkSection "Security scanning." {
    enabled = mkOpt t.bool "Enable OMP-native security scan planning, execution, and the read-only security:// resource namespace.";
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
