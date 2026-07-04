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
    dropUseless = mkOpt t.bool "Prune tool results flagged contextually useless (no matches, timed-out waits) once consumed.";
    midTurnEnabled = mkOpt t.bool "Check compaction thresholds at safe mid-turn tool-loop boundaries before the next request.";
    remoteStreamingV2Enabled = mkOpt t.bool "Use Responses streaming compaction for compatible remote compaction models.";
    v2RetainedMessageBudget = mkOpt num "Message-token budget retained by remote compaction V2.";
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

  snapcompact = mkSection "Experimental snapcompact inline imaging." {
    systemPrompt = mkOpt (t.enum [
      "none"
      "agents-md"
      "all"
    ]) "Render selected system prompt text as dense PNG image(s) for vision models.";
    toolResults = mkOpt t.bool "Render large historical tool results as dense PNG image(s) instead of text.";
    shape = mkOpt (t.enum [
      "auto"
      "8x8r-bw"
      "8x8r-sent"
      "8x8u-bw"
      "8x8u-sent"
      "6x6u-bw"
      "6x6u-sent"
      "5x8-bw"
      "5x8-sent"
      "6x12-dim"
      "8x13-bw"
      "8on16-bw"
      "8on22-bw"
      "11on16-bw"
      "silver16-bw"
      "doc-8on16-bw"
      "doc-8on16-sent"
      "doc-8on16-sent-dim"
    ]) "Frame shape snapcompact prints text with (auto picks per model).";
  };
}
