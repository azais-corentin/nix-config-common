{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.jcode;
  tomlFormat = pkgs.formats.toml { };

  inherit (lib) types;

  # ── Helpers ──────────────────────────────────────────────────────────────

  # Nullable option that defaults to null (so it gets pruned from config.toml
  # and jcode's own default kicks in upstream).
  mkOpt =
    type: description:
    lib.mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  # One TOML table, declared as a submodule whose typed options are merged
  # with a freeform escape hatch for forward-compat with new jcode keys.
  mkSection =
    description: options:
    lib.mkOption {
      type = types.submodule {
        freeformType = tomlFormat.type;
        inherit options;
      };
      default = { };
      inherit description;
    };

  # Recursively strip `null` values and empty attrsets so config.toml stays
  # minimal. Lists are walked element-wise but never collapsed when empty
  # (an explicitly-empty list is a meaningful override).
  pruneNulls =
    v:
    if lib.isAttrs v && !(lib.isDerivation v) then
      lib.pipe v [
        (lib.mapAttrs (_: pruneNulls))
        (lib.filterAttrs (_: x: x != null && !(lib.isAttrs x && x == { })))
      ]
    else if lib.isList v then
      map pruneNulls v
    else
      v;

  # ── Enum value sets (mirrors jcode-config-types serde renames) ───────────

  diffModes = [
    "off"
    "inline"
    "full-inline"
    "pinned"
    "file"
  ];
  diagramModes = [
    "none"
    "margin"
    "pinned"
  ];
  markdownSpacings = [
    "compact"
    "document"
  ];
  performanceTiers = [
    "auto"
    "full"
    "reduced"
    "minimal"
  ];
  transcriptModes = [
    "insert"
    "append"
    "replace"
    "send"
  ];
  sessionPickerActions = [
    "current-terminal"
    "new-terminal"
  ];
  updateChannels = [
    "stable"
    "main"
  ];
  websearchEngines = [
    "duckduckgo"
    "bing"
  ];
  openaiReasoningEfforts = [
    "none"
    "low"
    "medium"
    "high"
    "xhigh"
  ];
  anthropicReasoningEfforts = [
    "none"
    "low"
    "medium"
    "high"
    "max"
  ];
  openaiTransports = [
    "auto"
    "websocket"
    "https"
  ];
  openaiServiceTiers = [
    "priority"
    "flex"
    "off"
  ];
  openaiNativeCompactionModes = [
    "auto"
    "explicit"
    "off"
  ];
  crossProviderFailover = [
    "countdown"
    "manual"
  ];
  copilotPremiums = [
    "normal"
    "one"
    "zero"
  ];
  swarmSpawnModes = [
    "visible"
    "headless"
    "auto"
  ];
  compactionModes = [
    "reactive"
    "proactive"
    "semantic"
  ];
  namedProviderTypes = [
    "openai-compatible"
    "openrouter"
  ];
  namedProviderAuths = [
    "bearer"
    "header"
    "none"
  ];
  toolsProfiles = [
    "full"
    "minimal"
    "lite"
    "none"
    "off"
    "disabled"
  ];

  # ── Section submodules ───────────────────────────────────────────────────

  keybindingsOptions = {
    scroll_up = mkOpt types.str "Scroll up key (default: ctrl+k).";
    scroll_down = mkOpt types.str "Scroll down key (default: ctrl+j).";
    scroll_page_up = mkOpt types.str "Page up key (default: alt+u).";
    scroll_page_down = mkOpt types.str "Page down key (default: alt+d).";
    model_switch_next = mkOpt types.str "Model switch next key (default: ctrl+tab).";
    model_switch_prev = mkOpt types.str "Model switch previous key (default: ctrl+shift+tab).";
    effort_increase = mkOpt types.str "Effort increase key (default: alt+right).";
    effort_decrease = mkOpt types.str "Effort decrease key (default: alt+left).";
    centered_toggle = mkOpt types.str "Centered mode toggle key (default: alt+c).";
    scroll_prompt_up = mkOpt types.str "Scroll to previous prompt key (default: ctrl+[).";
    scroll_prompt_down = mkOpt types.str "Scroll to next prompt key (default: ctrl+]).";
    scroll_bookmark = mkOpt types.str "Scroll bookmark toggle key (default: ctrl+g).";
    scroll_up_fallback = mkOpt types.str "Scroll up fallback key (default: cmd+k).";
    scroll_down_fallback = mkOpt types.str "Scroll down fallback key (default: cmd+j).";
    workspace_left = mkOpt types.str "Workspace navigation left key (default: alt+h).";
    workspace_down = mkOpt types.str "Workspace navigation down key (default: alt+j).";
    workspace_up = mkOpt types.str "Workspace navigation up key (default: alt+k).";
    workspace_right = mkOpt types.str "Workspace navigation right key (default: alt+l).";
    session_picker_enter = mkOpt (types.enum sessionPickerActions) "Session picker Enter action; Ctrl+Enter performs the alternate.";
  };

  dictationOptions = {
    command = mkOpt types.str "Shell command to run; must print the transcript to stdout.";
    mode = mkOpt (types.enum transcriptModes) "How to apply the resulting transcript.";
    key = mkOpt types.str "Optional in-app hotkey to trigger dictation.";
    timeout_secs = mkOpt types.ints.unsigned "Maximum time to wait for the command to finish (0 = no timeout).";
  };

  nativeScrollbarsOptions = {
    chat = mkOpt types.bool "Show a native terminal scrollbar in the chat viewport.";
    side_panel = mkOpt types.bool "Show a native terminal scrollbar in the side panel.";
  };

  displayOptions = {
    diff_mode = mkOpt (types.enum diffModes) "How to display file diffs (off/inline/full-inline/pinned/file).";
    queue_mode = mkOpt types.bool "Queue mode by default — wait until done before sending.";
    auto_server_reload = mkOpt types.bool "Automatically reload the remote server when a newer binary is detected.";
    mouse_capture = mkOpt types.bool "Capture mouse events (enables scroll wheel, disables terminal selection).";
    debug_socket = mkOpt types.bool "Enable debug socket for external control.";
    centered = mkOpt types.bool "Center all content.";
    show_thinking = mkOpt types.bool "Show thinking/reasoning content by default.";
    diagram_mode = mkOpt (types.enum diagramModes) "How to display mermaid diagrams.";
    markdown_spacing = mkOpt (types.enum markdownSpacings) "Markdown block spacing style.";
    pin_images = mkOpt types.bool "Pin read images to side pane.";
    idle_animation = mkOpt types.bool "Show idle animation before first prompt.";
    prompt_entry_animation = mkOpt types.bool "Briefly animate user prompt line when it enters viewport.";
    disabled_animations = mkOpt (types.listOf types.str) "Disable specific animation variants by name.";
    diff_line_wrap = mkOpt types.bool "Wrap long lines in the pinned diff pane.";
    performance = mkOpt (types.enum performanceTiers) "Performance tier override.";
    animation_fps = mkOpt (types.ints.between 1 120) "FPS for animations (startup, idle donut).";
    redraw_fps = mkOpt (types.ints.between 1 120) "FPS for active redraw (processing, streaming).";
    prompt_preview = mkOpt types.bool "Show a truncated preview of the previous prompt when it scrolls out of view.";
    copy_badge_alt_label = mkOpt types.str "Override the Alt/Option label shown in copy badges (empty = auto).";
    native_scrollbars = mkSection "Native terminal scrollbar configuration." nativeScrollbarsOptions;
  };

  featuresOptions = {
    memory = mkOpt types.bool "Enable memory retrieval/extraction features.";
    swarm = mkOpt types.bool "Enable swarm coordination features.";
    message_timestamps = mkOpt types.bool "Inject timestamps into user messages and tool results sent to the model.";
    persist_memory_injections = mkOpt types.bool "Persist auto-recalled memory injections into normal session history instead of ephemeral suffix.";
    update_channel = mkOpt (types.enum updateChannels) "Update channel.";
  };

  websearchOptions = {
    engine = mkOpt (types.enum websearchEngines) "Preferred engine when the tool input does not specify one.";
    fallback_engines = mkOpt (types.listOf (types.enum websearchEngines)) "Keyless HTML engines to try after the preferred engine fails.";
    bing_api_key = mkOpt types.str "Optional Bing API key for primary Bing searches.";
    bing_api_key_env = mkOpt types.str "Environment variable containing the Bing API key.";
    bing_market = mkOpt types.str ''Bing market, e.g. "en-US" or "zh-CN".'';
  };

  toolsOptions = {
    profile = mkOpt (types.enum toolsProfiles) "Tool profile.";
    enabled = mkOpt (types.listOf types.str) ''Explicit allow-list. Use "*" or "all" for every tool.'';
    disabled = mkOpt (types.listOf types.str) "Tools to remove after applying profile/enabled.";
    disable_base_tools = mkOpt types.bool "Disable all built-in tools unless `enabled` is provided.";
  };

  authOptions = {
    trusted_external_sources = mkOpt (types.listOf types.str) "External auth source ids that the user has approved jcode to read/use.";
    trusted_external_source_paths = mkOpt (types.listOf types.str) "Path-bound approvals for external auth sources managed by other tools.";
  };

  providerOptions = {
    default_model = mkOpt types.str ''Default model to use (e.g. "claude-opus-4-6", "copilot:claude-opus-4.6").'';
    default_provider = mkOpt types.str "Default provider to use (claude|openai|copilot|openrouter).";
    openai_reasoning_effort = mkOpt (types.enum openaiReasoningEfforts) "Reasoning effort for OpenAI Responses API.";
    anthropic_reasoning_effort = mkOpt (types.enum anthropicReasoningEfforts) "Reasoning effort for Anthropic Messages API output_config.";
    openai_transport = mkOpt (types.enum openaiTransports) "OpenAI transport mode.";
    openai_service_tier = mkOpt (types.enum openaiServiceTiers) "OpenAI service tier override.";
    openai_native_compaction_mode = mkOpt (types.enum openaiNativeCompactionModes) "OpenAI native compaction mode.";
    openai_native_compaction_threshold_tokens = mkOpt types.ints.unsigned "Token threshold at which OpenAI auto native compaction triggers.";
    cross_provider_failover = mkOpt (types.enum crossProviderFailover) "How to handle cross-provider failover when the same input would be resent elsewhere.";
    same_provider_account_failover = mkOpt types.bool "Try another account on the same provider before falling back to a different provider.";
    copilot_premium = mkOpt (types.enum copilotPremiums) "Copilot premium request mode.";
  };

  namedProviderModelOptions = {
    id = lib.mkOption {
      type = types.str;
      description = "Model identifier as sent to the upstream provider.";
    };
    context_window = mkOpt types.ints.unsigned "Override context-window size for this model.";
    input = mkOpt (types.listOf types.str) "Input modalities accepted by this model.";
  };

  namedProviderType = types.submodule {
    freeformType = tomlFormat.type;
    options = {
      type = mkOpt (types.enum namedProviderTypes) "Provider implementation.";
      base_url = mkOpt types.str "Base URL of the OpenAI-compatible endpoint.";
      api = mkOpt types.str "API selector when the provider supports multiple variants.";
      auth = mkOpt (types.enum namedProviderAuths) "Authentication scheme.";
      auth_header = mkOpt types.str ''Header name for `auth = "header"`.'';
      api_key_env = mkOpt types.str "Environment variable containing the API key.";
      api_key = mkOpt types.str "API key (inline; prefer api_key_env).";
      env_file = mkOpt types.str "Path to a dotenv file with the API key.";
      default_model = mkOpt types.str "Default model name for this provider.";
      requires_api_key = mkOpt types.bool "Override whether an API key is required.";
      provider_routing = mkOpt types.bool "Enable provider-routing metadata pass-through.";
      model_catalog = mkOpt types.bool "Fetch the model catalog dynamically.";
      allow_provider_pinning = mkOpt types.bool "Allow pinning specific upstream providers.";
      models = mkOpt (types.listOf (
        types.submodule {
          freeformType = tomlFormat.type;
          options = namedProviderModelOptions;
        }
      )) "Per-model overrides for this provider.";
    };
  };

  agentsOptions = {
    swarm_model = mkOpt types.str "Default model override for spawned swarm/subagent sessions.";
    swarm_spawn_mode = mkOpt (types.enum swarmSpawnModes) "Default terminal mode for swarm-created agents.";
    memory_model = mkOpt types.str "Default model override for the memory sidecar.";
    memory_sidecar_enabled = mkOpt types.bool "Whether memory should use the sidecar for relevance/extraction.";
  };

  ambientOptions = {
    enabled = mkOpt types.bool "Enable ambient mode.";
    provider = mkOpt types.str "Provider override (default: auto-select).";
    model = mkOpt types.str "Model override (default: provider's strongest).";
    allow_api_keys = mkOpt types.bool "Allow API key usage (default: false, only OAuth).";
    api_daily_budget = mkOpt types.ints.unsigned "Daily token budget when using API keys.";
    min_interval_minutes = mkOpt types.ints.unsigned "Minimum interval between cycles in minutes.";
    max_interval_minutes = mkOpt types.ints.unsigned "Maximum interval between cycles in minutes.";
    pause_on_active_session = mkOpt types.bool "Pause ambient when user has active session.";
    proactive_work = mkOpt types.bool "Enable proactive work vs garden-only.";
    work_branch_prefix = mkOpt types.str "Proactive work branch prefix.";
    visible = mkOpt types.bool "Show ambient cycle in a terminal window.";
  };

  safetyOptions = {
    ntfy_topic = mkOpt types.str "ntfy.sh topic name (required for push notifications).";
    ntfy_server = mkOpt types.str "ntfy.sh server URL.";
    desktop_notifications = mkOpt types.bool "Enable desktop notifications via notify-send.";
    email_enabled = mkOpt types.bool "Enable email notifications.";
    email_to = mkOpt types.str "Email recipient.";
    email_smtp_host = mkOpt types.str "SMTP host (e.g. smtp.gmail.com).";
    email_smtp_port = mkOpt types.port "SMTP port.";
    email_from = mkOpt types.str "Email sender address.";
    email_password = mkOpt types.str "SMTP password (prefer JCODE_SMTP_PASSWORD env var).";
    email_imap_host = mkOpt types.str "IMAP host for receiving email replies.";
    email_imap_port = mkOpt types.port "IMAP port.";
    email_reply_enabled = mkOpt types.bool "Enable email reply → agent directive feature.";
    telegram_enabled = mkOpt types.bool "Enable Telegram notifications.";
    telegram_bot_token = mkOpt types.str "Telegram bot token (from @BotFather).";
    telegram_chat_id = mkOpt types.str "Telegram chat ID to send messages to.";
    telegram_reply_enabled = mkOpt types.bool "Enable Telegram reply → agent directive feature.";
    discord_enabled = mkOpt types.bool "Enable Discord notifications.";
    discord_bot_token = mkOpt types.str "Discord bot token.";
    discord_channel_id = mkOpt types.str "Discord channel ID to send messages to.";
    discord_bot_user_id = mkOpt types.str "Discord bot user ID (for filtering own messages in polling).";
    discord_reply_enabled = mkOpt types.bool "Enable Discord reply → agent directive feature.";
  };

  gatewayOptions = {
    enabled = mkOpt types.bool "Enable the WebSocket gateway.";
    port = mkOpt types.port "TCP port to listen on.";
    bind_addr = mkOpt types.str "Bind address.";
  };

  compactionOptions = {
    mode = mkOpt (types.enum compactionModes) "Compaction mode.";
    lookahead_turns = mkOpt types.ints.unsigned "[proactive] Number of turns to look ahead when projecting token growth.";
    ewma_alpha = mkOpt (types.numbers.between 0.0 1.0) "[proactive] EWMA alpha for token growth smoothing.";
    proactive_floor = mkOpt (types.numbers.between 0.0 1.0) "[proactive/semantic] Minimum context fill level before any proactive check fires.";
    min_samples = mkOpt types.ints.unsigned "[proactive/semantic] Minimum number of token snapshots needed before proactive check.";
    stall_window = mkOpt types.ints.unsigned "[proactive/semantic] Stable turns (no growth) before suppressing proactive compact.";
    min_turns_between_compactions = mkOpt types.ints.unsigned "[proactive/semantic] Minimum turns between two compactions (cooldown).";
    topic_shift_threshold = mkOpt (types.numbers.between 0.0 1.0) "[semantic] Cosine similarity threshold below which a topic shift is detected.";
    relevance_keep_threshold = mkOpt (types.numbers.between 0.0 1.0) "[semantic] Cosine similarity above which a message is kept verbatim.";
    goal_window_turns = mkOpt types.ints.unsigned "[semantic] Number of recent turns used to build the current-goal embedding.";
  };

  autoreviewOptions = {
    enabled = mkOpt types.bool "Enable autoreview by default for new/resumed sessions.";
    model = mkOpt types.str "Optional model override for autoreview reviewer sessions.";
  };

  autojudgeOptions = {
    enabled = mkOpt types.bool "Enable autojudge by default for new/resumed sessions.";
    model = mkOpt types.str "Optional model override for autojudge sessions.";
  };

  # ── Skills (unchanged) ───────────────────────────────────────────────────

  # Parse "github:owner/repo/subdir@ref" → { owner, repo, subdir, ref } or null.
  parseGithubRef =
    s:
    let
      m = builtins.match "github:([^/]+)/([^/@]+)(/[^@]*)?@(.+)" s;
    in
    if m == null then
      null
    else
      {
        owner = builtins.elemAt m 0;
        repo = builtins.elemAt m 1;
        # Strip leading slash from subdir capture, default to ""
        subdir =
          let
            raw = builtins.elemAt m 2;
          in
          if raw == null then "" else lib.removePrefix "/" raw;
        ref = builtins.elemAt m 3;
      };

  # 40-char lowercase hex → treat as commit SHA (allows pure eval with `rev`)
  isCommitHash = s: builtins.match "[0-9a-f]{40}" s != null;

  # Fetch a GitHub repo and return the store path to the (optionally nested) subdir.
  fetchGithubSkill =
    {
      owner,
      repo,
      subdir,
      ref,
    }:
    let
      fetched = builtins.fetchGit (
        {
          url = "https://github.com/${owner}/${repo}";
        }
        // (if isCommitHash ref then { rev = ref; } else { inherit ref; })
      );
      base = builtins.toString fetched;
    in
    if subdir != "" then "${base}/${subdir}" else base;

  # Submodule type for structured remote skill sources.
  skillSrcSubmodule = types.submodule {
    options = {
      src = lib.mkOption {
        type = types.either types.path types.str;
        description = "Store path or fetcher result (e.g. pkgs.fetchFromGitHub, builtins.fetchGit, flake input).";
      };
      subdir = lib.mkOption {
        type = types.str;
        default = "";
        description = "Subdirectory within src containing the skill.";
      };
    };
  };

  # Union type covering all skill value forms.
  skillType = types.oneOf [
    types.path
    types.lines
    skillSrcSubmodule
  ];

  # Skills support directories (with assets), single files, inline strings,
  # github: shorthand refs, and structured { src, subdir } attrsets.
  mkSkillEntries =
    attrs:
    lib.mapAttrs' (
      name: content:
      # 1. Nix path to directory → recursive symlink
      if lib.isPath content && lib.pathIsDirectory content then
        lib.nameValuePair ".jcode/skills/${name}" {
          source = content;
          recursive = true;
        }
      # 2. Nix path to file → SKILL.md symlink
      else if lib.isPath content then
        lib.nameValuePair ".jcode/skills/${name}/SKILL.md" {
          source = content;
        }
      # 3. String: github: shorthand → fetch + recursive symlink
      else if lib.isString content && parseGithubRef content != null then
        let
          ref = parseGithubRef content;
        in
        lib.nameValuePair ".jcode/skills/${name}" {
          source = fetchGithubSkill ref;
          recursive = true;
        }
      # 4. String: inline SKILL.md content
      else if lib.isString content then
        lib.nameValuePair ".jcode/skills/${name}/SKILL.md" {
          text = content;
        }
      # 5. Attrset: structured { src, subdir } → recursive symlink
      else
        let
          path = if content.subdir != "" then "${content.src}/${content.subdir}" else "${content.src}";
        in
        lib.nameValuePair ".jcode/skills/${name}" {
          source = path;
          recursive = true;
        }
    ) attrs;
in
{
  options.jcode = {
    enable = lib.mkEnableOption "jcode declarative configuration";

    keybindings = mkSection "Keybinding configuration." keybindingsOptions;
    dictation = mkSection "External dictation / speech-to-text integration." dictationOptions;
    display = mkSection "Display / UI configuration." displayOptions;
    features = mkSection "Runtime feature toggles." featuresOptions;
    websearch = mkSection "Web search tool configuration." websearchOptions;
    tools = mkSection "Built-in tool exposure configuration." toolsOptions;
    auth = mkSection "Auth trust / consent configuration." authOptions;
    provider = mkSection "Provider configuration." providerOptions;
    providers = lib.mkOption {
      type = types.attrsOf namedProviderType;
      default = { };
      description = "Named provider profiles, keyed by profile name.";
    };
    agents = mkSection "Agent-specific model defaults." agentsOptions;
    ambient = mkSection "Ambient mode configuration." ambientOptions;
    safety = mkSection "Safety system & notification configuration." safetyOptions;
    gateway = mkSection "WebSocket gateway configuration (for iOS/web clients)." gatewayOptions;
    compaction = mkSection "Compaction configuration." compactionOptions;
    autoreview = mkSection "Automatic end-of-turn code review configuration." autoreviewOptions;
    autojudge = mkSection "Automatic end-of-turn execution judging configuration." autojudgeOptions;

    skills = lib.mkOption {
      type = types.attrsOf skillType;
      default = { };
      description = ''
        Skills installed to ~/.jcode/skills/<name>/.
        Each value is one of:
        - A path to a SKILL.md file (symlinked as skills/<name>/SKILL.md)
        - A path to a directory containing SKILL.md and assets (symlinked recursively)
        - An inline string (written as skills/<name>/SKILL.md)
        - A "github:owner/repo/subdir@ref" string (fetched and symlinked recursively)
        - An attrset { src; subdir; } for pre-fetched sources (symlinked recursively)
      '';
    };

    promptOverlay = lib.mkOption {
      type = types.nullOr (types.either types.lines types.path);
      default = null;
      description = "Optional global prompt overlay written to ~/.jcode/prompt-overlay.md.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.file = lib.mkMerge [
      (
        let
          raw = {
            inherit (cfg)
              keybindings
              dictation
              display
              features
              websearch
              tools
              auth
              provider
              providers
              agents
              ambient
              safety
              gateway
              compaction
              autoreview
              autojudge
              ;
          };
          pruned = pruneNulls raw;
        in
        lib.mkIf (pruned != { }) {
          ".jcode/config.toml".source = tomlFormat.generate "jcode-config.toml" pruned;
        }
      )
      (lib.mkIf (cfg.skills != { }) (mkSkillEntries cfg.skills))
      (lib.mkIf (cfg.promptOverlay != null) {
        ".jcode/prompt-overlay.md" =
          if lib.isPath cfg.promptOverlay then
            { source = cfg.promptOverlay; }
          else
            { text = cfg.promptOverlay; };
      })
    ];
  };
}
