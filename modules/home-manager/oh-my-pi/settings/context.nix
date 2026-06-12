# Context settings: context promotion, compaction, branch summaries, TTSR.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;
in
{
  contextPromotion = mkSection "Context promotion on overflow." {
    enabled = mkOpt t.bool "Promote to a larger-context model on overflow instead of compacting.";
  };

  compaction = mkSection "Context compaction." {
    enabled = mkOpt t.bool "Automatically compact context when it gets too large.";
    strategy = mkOpt (t.enum [
      "context-full"
      "handoff"
      "shake"
      "snapcompact"
      "off"
    ]) "Compaction strategy.";
    thresholdPercent = mkOpt num "Percent threshold for context maintenance (-1 = legacy reserve-based).";
    thresholdTokens = mkOpt num "Fixed token limit for context maintenance (-1 = use percentage).";
    handoffSaveToDisk = mkOpt t.bool "Save generated handoff documents to markdown files.";
    remoteEnabled = mkOpt t.bool "Use remote compaction endpoints when available.";
    reserveTokens = mkOpt num "Tokens reserved below the limit before compaction.";
    keepRecentTokens = mkOpt num "Recent tokens always kept during compaction.";
    autoContinue = mkOpt t.bool "Automatically continue after compaction.";
    remoteEndpoint = mkOpt t.str "Remote compaction endpoint URL.";
    idleEnabled = mkOpt t.bool "Compact context while idle when token count exceeds threshold.";
    idleThresholdTokens = mkOpt num "Token count above which idle compaction triggers.";
    idleTimeoutSeconds = mkOpt num "Seconds to wait while idle before compacting.";
    supersedeReads = mkOpt t.bool "Prune older read results when the same file is read again (cache-aware, runs every turn).";
  };

  branchSummary = mkSection "Branch summaries." {
    enabled = mkOpt t.bool "Prompt to summarize when leaving a branch.";
    reserveTokens = mkOpt num "Tokens reserved for branch summaries.";
  };

  ttsr = mkSection "Time Traveling Stream Rules." {
    enabled = mkOpt t.bool "Interrupt the agent when output matches patterns.";
    contextMode = mkOpt (t.enum [
      "discard"
      "keep"
    ]) "What to do with partial output when TTSR triggers.";
    interruptMode = mkOpt (t.enum [
      "never"
      "prose-only"
      "tool-only"
      "always"
    ]) "When to interrupt mid-stream vs inject a warning after completion.";
    repeatMode = mkOpt (t.enum [
      "once"
      "after-gap"
    ]) "How rules can repeat: once per session or after a message gap.";
    repeatGap = mkOpt num "Messages before a rule can trigger again.";
    builtinRules = mkOpt t.bool "Load the default rules shipped with the agent.";
    disabledRules = mkOpt (t.listOf t.str) "Rule names to ignore entirely.";
  };
}
