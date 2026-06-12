# Model settings: thinking/prompt, sampling parameters, service tier, retries
# and thinking budgets.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;
in
{
  defaultThinkingLevel = mkOpt (t.enum [
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "auto"
  ]) "Reasoning depth for thinking-capable models.";
  hideThinkingBlock = mkOpt t.bool "Hide thinking blocks in assistant responses.";
  repeatToolDescriptions = mkOpt t.bool "Render full tool descriptions in the system prompt instead of a name list.";
  includeModelInPrompt = mkOpt t.bool "Surface the active model id in the system prompt so the agent knows which model it is.";

  temperature = mkOpt num "Sampling temperature (-1 = provider default).";
  topP = mkOpt num "Nucleus sampling cutoff (-1 = provider default).";
  topK = mkOpt num "Sample from top-K tokens (-1 = provider default).";
  minP = mkOpt num "Minimum probability threshold (-1 = provider default).";
  presencePenalty = mkOpt num "Penalty for introducing already-present tokens (-1 = provider default).";
  repetitionPenalty = mkOpt num "Penalty for repeated tokens (-1 = provider default).";

  serviceTier = mkOpt (t.enum [
    "none"
    "auto"
    "default"
    "flex"
    "scale"
    "priority"
    "openai-only"
    "claude-only"
  ]) "Processing priority hint (none = omit service_tier).";

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
  };
}
