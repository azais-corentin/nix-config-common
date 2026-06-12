# Memory settings: legacy memories pipeline, the backend selector, the Mnemopi
# local SQLite backend and the Hindsight remote memory service.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;

  scoping = t.enum [
    "global"
    "per-project"
    "per-project-tagged"
  ];
in
{
  memories = mkSection "Legacy local-memory rollout pipeline tuning." {
    enabled = mkOpt t.bool "Legacy local-memory enable flag (kept for back-compat migration).";
    maxRolloutsPerStartup = mkOpt num "Max rollouts scanned per startup.";
    maxRolloutAgeDays = mkOpt num "Maximum rollout age in days.";
    minRolloutIdleHours = mkOpt num "Minimum idle hours before a rollout is processed.";
    threadScanLimit = mkOpt num "Maximum threads scanned.";
    maxRawMemoriesForGlobal = mkOpt num "Maximum raw memories considered for the global summary.";
    stage1Concurrency = mkOpt num "Stage-1 worker concurrency.";
    stage1LeaseSeconds = mkOpt num "Stage-1 lease duration in seconds.";
    stage1RetryDelaySeconds = mkOpt num "Stage-1 retry delay in seconds.";
    phase2LeaseSeconds = mkOpt num "Phase-2 lease duration in seconds.";
    phase2RetryDelaySeconds = mkOpt num "Phase-2 retry delay in seconds.";
    phase2HeartbeatSeconds = mkOpt num "Phase-2 heartbeat interval in seconds.";
    rolloutPayloadPercent = mkOpt num "Fraction of the rollout payload retained.";
    phase1InputTokenLimit = mkOpt num "Phase-1 input token limit.";
    fallbackTokenLimit = mkOpt num "Fallback token limit.";
    summaryInjectionTokenLimit = mkOpt num "Summary injection token limit.";
  };

  memory = mkSection "Memory backend selector." {
    backend = mkOpt (t.enum [
      "off"
      "local"
      "hindsight"
      "mnemopi"
    ]) "Off, local summary pipeline, Mnemopi SQLite, or Hindsight remote memory.";
  };

  mnemopi = mkSection "Mnemopi local SQLite memory backend." {
    dbPath = mkOpt t.str "Optional SQLite DB path (defaults to the agent memories directory).";
    bank = mkOpt t.str "Optional shared bank base name.";
    scoping = mkOpt scoping "Bank scoping: global, per-project, or per-project-tagged.";
    autoRecall = mkOpt t.bool "Recall local memories into the first turn of each session.";
    autoRetain = mkOpt t.bool "Retain completed conversation turns into local Mnemopi memory.";
    noEmbeddings = mkOpt t.bool "Force deterministic FTS-only recall instead of vector embeddings.";
    embeddingModel = mkOpt t.str "Optional embedding model override.";
    embeddingApiUrl = mkOpt t.str "Optional OpenAI-compatible embedding endpoint.";
    embeddingApiKey = mkOpt t.str "Optional embedding API key.";
    llmMode = mkOpt (t.enum [
      "none"
      "smol"
      "remote"
    ]) "Use no LLM, the configured smol model, or a remote OpenAI-compatible endpoint.";
    llmBaseUrl = mkOpt t.str "Optional OpenAI-compatible LLM endpoint for remote mode.";
    llmApiKey = mkOpt t.str "Optional LLM API key for remote mode.";
    llmModel = mkOpt t.str "Optional LLM model name for remote mode.";
    retainEveryNTurns = mkOpt num "Retain every N turns.";
    recallLimit = mkOpt num "Maximum memories recalled per query.";
    recallContextTurns = mkOpt num "Conversation turns used as recall context.";
    recallMaxQueryChars = mkOpt num "Maximum recall query length in characters.";
    injectionTokenLimit = mkOpt num "Recall injection token limit.";
    debug = mkOpt t.bool "Enable Mnemopi debug logging.";
  };

  hindsight = mkSection "Hindsight remote memory service." {
    apiUrl = mkOpt t.str "Hindsight server URL (Cloud or self-hosted).";
    apiToken = mkOpt t.str "Hindsight API token.";
    bankId = mkOpt t.str "Memory bank identifier (default: project name).";
    bankIdPrefix = mkOpt t.str "Prefix applied to derived bank ids.";
    scoping = mkOpt scoping "Bank scoping: global, per-project, or per-project-tagged.";
    bankMission = mkOpt t.str "Optional bank mission string.";
    retainMission = mkOpt t.str "Optional retain mission string.";
    autoRecall = mkOpt t.bool "Recall memories on the first turn of each session.";
    autoRetain = mkOpt t.bool "Retain transcript every N turns and at session boundaries.";
    retainMode = mkOpt (t.enum [
      "full-session"
      "last-turn"
    ]) "full-session = one document per session, last-turn = chunked.";
    retainEveryNTurns = mkOpt num "Retain every N turns.";
    retainOverlapTurns = mkOpt num "Overlap turns between chunked retains.";
    retainContext = mkOpt t.str "Retain context label (default: omp).";
    recallBudget = mkOpt (t.enum [
      "low"
      "mid"
      "high"
    ]) "Recall budget tier.";
    recallMaxTokens = mkOpt num "Maximum recall tokens injected.";
    recallContextTurns = mkOpt num "Conversation turns used as recall context.";
    recallMaxQueryChars = mkOpt num "Maximum recall query length in characters.";
    recallTypes = mkOpt (t.listOf t.str) "Memory types to recall (default: world, experience).";
    debug = mkOpt t.bool "Enable Hindsight debug logging.";
    mentalModelsEnabled = mkOpt t.bool "Read curated reflect summaries into developer instructions at boot.";
    mentalModelAutoSeed = mkOpt t.bool "Auto-create built-in mental models that do not yet exist on the bank.";
    mentalModelRefreshIntervalMs = mkOpt num "Mental model refresh interval in milliseconds.";
    mentalModelMaxRenderChars = mkOpt num "Maximum characters rendered for mental models.";
  };
}
