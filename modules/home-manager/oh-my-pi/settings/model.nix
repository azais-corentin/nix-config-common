# Model settings: thinking/prompt, sampling parameters, service tier, retries
# and thinking budgets.
{ lib, helpers }:
let
  inherit (helpers)
    mkOpt
    mkSection
    subType
    num
    ;
  t = lib.types;
  serviceTierInherit = t.enum [
    "inherit"
    "none"
    "auto"
    "default"
    "flex"
    "scale"
    "priority"
    "ultrafast"
  ];
  thinkingLevel = t.enum [
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "auto"
    "max"
  ];
in
{
  defaultThinkingLevel = mkOpt thinkingLevel "Reasoning depth for thinking-capable models.";

  modelPresets = mkOpt (t.attrsOf (subType {
    modelRoles = lib.mkOption {
      type = t.attrsOf t.str;
      description = "Role → model-selector assignments re-applied as a whole (same value syntax as modelRoles).";
    };
    defaultThinkingLevel = mkOpt thinkingLevel "defaultThinkingLevel applied with the preset; unset leaves the current level alone.";
  })) "Named model presets switched with /modelpreset switch <name> (no settings-panel UI).";

  hideThinkingBlock = mkOpt t.bool "Hide thinking blocks in assistant responses.";
  expandThinkingBlocks = mkOpt t.bool "Keep finished thinking blocks expanded instead of collapsing them when the turn ends (native rendering only).";
  includeModelInPrompt = mkOpt t.bool "Surface the active model id in the system prompt so the agent knows which model it is.";
  skillful = mkOpt t.bool "List available skills in the system prompt; disable to save context (per-session /skillful).";
  inlineToolDescriptors =
    mkOpt
      (t.enum [
        "auto"
        "on"
        "off"
      ])
      "Render full tool descriptors in the system prompt and strip descriptions from provider tool schemas (auto = on for Gemini, off otherwise).";
  includeWorkspaceTree = mkOpt t.bool "Render the workspace directory tree in the system prompt (can bust prompt caching when files change).";
  omitThinking = mkOpt t.bool "Ask upstream providers to omit thinking summaries entirely (where supported).";
  proseOnlyThinking = mkOpt t.bool "Omit code blocks from thinking summaries, replacing them with an ellipsis.";
  externalThinking = mkOpt t.bool "Private scratchpad thinking not shown to the user; disables supported GPT, Claude and Gemini reasoning. At your own risk: providers have flagged this request shape as abuse, up to account-level enforcement.";
  personality = mkOpt (t.enum [
    "default"
    "friendly"
    "pragmatic"
    "none"
  ]) "Assistant personality/tone preset.";
  textVerbosity = mkOpt (t.enum [
    "low"
    "medium"
    "high"
  ]) "OpenAI Responses/Codex response verbosity.";

  temperature = mkOpt num "Sampling temperature (-1 = provider default).";
  topP = mkOpt num "Nucleus sampling cutoff (-1 = provider default).";
  topK = mkOpt num "Sample from top-K tokens (-1 = provider default).";
  minP = mkOpt num "Minimum probability threshold (-1 = provider default).";
  presencePenalty = mkOpt num "Penalty for introducing already-present tokens (-1 = provider default).";
  repetitionPenalty = mkOpt num "Penalty for repeated tokens (-1 = provider default).";

  retry = mkSection "API retry behaviour." {
    enabled = mkOpt t.bool "Retry on API errors.";
    modelFallback = mkOpt t.bool "Allow retry recovery to switch to configured fallback models.";
    maxRetries = mkOpt num "Maximum retry attempts on API errors.";
    baseDelayMs = mkOpt num "Base backoff delay in milliseconds.";
    maxDelayMs = mkOpt num "Maximum wait between retries, in ms (fail fast past this).";
    fallbackChains = mkOpt (t.attrsOf (t.listOf t.str)) "Fallback chains keyed by model role, provider/model selector, provider/* wildcard, or id-prefixed wildcard such as openrouter/google/*.";
    fallbackRevertPolicy = mkOpt (t.enum [
      "cooldown-expiry"
      "never"
    ]) "When to return to the primary model after a fallback.";
    fallbackOn =
      mkOpt
        (t.enum [
          "any"
          "usage-limit"
          "except-usage-limit"
        ])
        "Which failed requests may switch to a configured fallback model: any, only quota errors (usage-limit), or only non-quota errors (except-usage-limit).";
    usageAwareFallback = mkOpt t.bool "Prefer same-provider accounts, then configured fallback models, before a hard usage limit (coding-plan quota reports only).";
    usageReservePct = mkOpt num "Treat a coding-plan model as near its limit below this remaining percentage.";
    usageReservePolicy = mkOpt (t.enum [
      "confirm"
      "auto"
      "fail-closed"
    ]) "Action when every same-provider coding-plan account is inside the reserve margin.";
    waitForUsageReset = mkOpt t.bool "On a provider usage-limit reset time (5-hour or weekly quota windows), sleep until the reset instead of failing fast past retry.maxDelayMs; waits are abortable but also hold subagents.";
    rateLimitWalksChain = mkOpt t.bool "On a rate limit, walk retry.fallbackChains even for a turn whose thinking is signed by the failing model (off: such a turn keeps retrying the rate-limited model until retry.maxRetries is spent).";
  };

  thinkingBudgets = mkSection "Token budgets per thinking level (budget-mode models)." {
    minimal = mkOpt num "Token budget for the minimal thinking level.";
    low = mkOpt num "Token budget for the low thinking level.";
    medium = mkOpt num "Token budget for the medium thinking level.";
    high = mkOpt num "Token budget for the high thinking level.";
    xhigh = mkOpt num "Token budget for the xhigh thinking level.";
    max = mkOpt num "Token budget for the max thinking level.";
  };

  advisor = mkSection "Passive advisor model that reviews each turn." {
    enabled = mkOpt t.bool "Pair a second model (advisor role) that passively reviews each turn and injects notes.";
    immuneTurns = mkOpt num "After an advisor concern/blocker interrupts, route further ones non-interruptingly for this many primary turns.";
    syncBacklog =
      mkOpt
        (t.enum [
          "off"
          "1"
          "3"
          "5"
          "strict"
        ])
        "Pause the main agent until the advisor backlog falls below this many turns: numeric thresholds cap each wait at 30s, strict waits for every scheduled review without a wall-clock cap.";
    reviewMode =
      mkOpt
        (t.enum [
          "turn"
          "agent-end"
        ])
        "Advisor cadence when no WATCHDOG.yml roster is present: turn reviews every primary update, agent-end only final yields.";
    reviewInterval = mkOpt t.ints.positive "Advisor cadence when no WATCHDOG.yml roster is present: review every Nth eligible primary update (skipped updates ride along with the next review).";
    maxNotesPerUpdate = mkOpt num "Maximum non-blocker advice notes accepted per advisor prompt update (1-32); blockers are exempt.";
    evictStaleResults = mkOpt t.bool "Before each review, replace the advisor's read/grep/glob output from older reviews with a short placeholder (the latest review is kept).";
    continueSeverity =
      mkOpt
        (t.enum [
          "nit"
          "concern"
          "blocker"
        ])
        "Minimum severity of an advisor note that wakes the agent after it finished with a final answer (upstream default: concern); lower-severity notes stay as a card at the end of the transcript and reach the agent with the next message.";
  };

  prewalk = mkSection "Prewalk: strong model plans, cheap model implements." {
    enabled = mkOpt t.bool "Start on the active model, then hand off to prewalk.into at the first edit/write after the plan nudge's todo list exists (per-session --prewalk / --no-prewalk override).";
    from = mkOpt t.str "Model or role that /prewalk restart returns to for planning (upstream default: @default).";
    into = mkOpt t.str "Model or role prewalk hands off to at the first edit/write: /prewalk, /prewalk restart, Enable Prewalk and --prewalk (upstream default: @smol). Auto-prewalk uses prewalk.autoTarget.";
    auto =
      mkOpt
        (t.enum [
          "off"
          "suggest"
          "on"
        ])
        "Ask the native judge (judge role) whether each new top-level user task front-loads its hard reasoning: suggest reports the decision only, on also arms a handoff to prewalk.autoTarget. Needs a native judge; independent of prewalk.enabled.";
    autoTarget = mkOpt t.str "Model or role auto-prewalk hands off to at the first edit/write (upstream default: @smol).";
  };

  judgment = mkSection "Native judge calls." {
    attemptTimeoutMs = mkOpt t.ints.positive "Total provider budget in ms for one native judge candidate, including setup and retries (upstream default: 3000).";
  };

  tier = mkSection "Per-family processing tier (service_tier)." {
    openai =
      mkOpt
        (t.enum [
          "none"
          "auto"
          "default"
          "flex"
          "scale"
          "priority"
          "ultrafast"
        ])
        "Processing tier for OpenAI/Codex requests and OpenAI-family OpenRouter models (none = omit service_tier).";
    anthropic = mkOpt (t.enum [
      "none"
      "priority"
    ]) "Processing tier for Anthropic requests (none = omit service_tier).";
    google =
      mkOpt
        (t.enum [
          "none"
          "flex"
          "priority"
        ])
        "Processing tier for Gemini (AI Studio + Vertex) and Google-family OpenRouter models (none = omit).";
    subagent = mkOpt serviceTierInherit "Service tier for spawned task/eval subagents (inherit = match the main agent's live per-family tiers).";
    advisor = mkOpt serviceTierInherit "Service tier for the advisor model (none = standard; inherit = match the main agent).";
  };

  model = mkSection "Model runtime guards." {
    loopGuard = mkSection "Stream loop detection (Gemini/DeepSeek)." {
      enabled = mkOpt t.bool "Enable automatic stream loop detection for Gemini and DeepSeek models.";
      checkAssistantContent = mkOpt t.bool "Apply loop guard to assistant prose messages in addition to thinking logs.";
      toolCallReminder = mkOpt t.bool "When a Gemini reasoning stream emits many planning headers without a tool call, interrupt and inject a reminder to issue one (requires loopGuard.enabled).";
    };
    toolCallLoopGuard = mkSection "Cross-turn repeated tool-call loop guard." {
      enabled = mkOpt t.bool "Detect consecutive identical tool calls across turns and inject a corrective steer.";
      threshold = mkOpt num "Consecutive identical tool calls required before the steer is injected.";
      exemptTools = mkOpt (t.listOf t.str) "Tool names that may repeat without triggering the guard (default: hub).";
    };
  };
}
