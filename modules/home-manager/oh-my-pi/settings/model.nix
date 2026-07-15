# Model settings: thinking/prompt, sampling parameters, service tier, retries
# and thinking budgets.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;
  serviceTierInherit = t.enum [
    "inherit"
    "none"
    "auto"
    "default"
    "flex"
    "scale"
    "priority"
  ];
in
{
  defaultThinkingLevel = mkOpt (t.enum [
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "auto"
    "max"
  ]) "Reasoning depth for thinking-capable models.";
  hideThinkingBlock = mkOpt t.bool "Hide thinking blocks in assistant responses.";
  includeModelInPrompt = mkOpt t.bool "Surface the active model id in the system prompt so the agent knows which model it is.";
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
    fallbackChains = mkOpt (t.attrsOf (t.listOf t.str)) "Per-model fallback chains.";
    fallbackRevertPolicy = mkOpt (t.enum [
      "cooldown-expiry"
      "never"
    ]) "When to return to the primary model after a fallback.";
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
    subagents = mkOpt t.bool "Also enable the advisor on spawned task/eval subagents.";
    immuneTurns = mkOpt num "After an advisor concern/blocker interrupts, route further ones non-interruptingly for this many primary turns.";
    syncBacklog = mkOpt (t.enum [
      "off"
      "1"
      "3"
      "5"
    ]) "Pause the main agent up to 30s if the advisor falls behind by this many turns.";
  };

  prewalk = mkSection "Prewalk: strong model plans, cheap model implements." {
    enabled = mkOpt t.bool "Start on the active model, then hand off to the smol role at the first edit/write after the plan nudge's todo list exists (per-session --prewalk / --no-prewalk override).";
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
