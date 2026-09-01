# Providers settings: secret handling, web/image/tiny-model provider selection,
# append-only context, Exa, SearXNG, live voice and the commit changelog knobs.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;

  tinyMemoryModels = [
    "online"
    "qwen3-1.7b"
    "llama3.2:3b"
    "gemma-3-1b"
    "qwen2.5-1.5b"
    "lfm2-1.2b"
  ];

  liveVoices = [
    "arbor"
    "breeze"
    "cove"
    "ember"
    "juniper"
    "maple"
    "sol"
    "spruce"
    "vale"
  ];

  kokoroVoices = [
    "af_heart"
    "af_bella"
    "af_nicole"
    "af_aoede"
    "af_kore"
    "af_sarah"
    "am_michael"
    "am_fenrir"
    "am_puck"
    "bf_emma"
    "bm_george"
    "bm_fable"
  ];
in
{
  secrets = mkSection "Secret handling." {
    enabled = mkOpt t.bool "Obfuscate secrets before sending to AI providers.";
  };

  providers = mkSection "Provider selection for built-in tools." {
    webSearchOrder =
      mkOpt
        (t.listOf (
          t.enum [
            "perplexity"
            "gemini"
            "anthropic"
            "codex"
            "xai"
            "zai"
            "exa"
            "tinyfish"
            "jina"
            "kagi"
            "tavily"
            "firecrawl"
            "brave"
            "kimi"
            "parallel"
            "synthetic"
            "searxng"
            "startpage"
            "duckduckgo"
            "ecosia"
            "google"
            "mojeek"
            "public"
          ]
        ))
        "Prioritized providers for the web_search tool; unlisted providers keep their default order afterward.";
    imageOrder =
      mkOpt
        (t.listOf (
          t.enum [
            "openai"
            "openai-codex"
            "antigravity"
            "xai"
            "gemini"
            "openrouter"
          ]
        ))
        "Prioritized providers for image generation; unlisted providers follow the active session provider and the built-in order.";
    tinyModel = mkOpt (t.enum [
      "online"
      "lfm2-350m"
      "qwen3-0.6b"
      "gemma-270m"
      "qwen2.5-0.5b"
      "lfm2-700m"
    ]) "Session-title model: online pi/smol or a local on-device model.";
    tinyModelDevice = mkOpt (t.enum [
      "default"
      "gpu"
      "cpu"
      "metal"
      "webgpu"
      "cuda"
      "dml"
      "coreml"
      "auto"
      "wasm"
      "webnn"
      "webnn-gpu"
      "webnn-cpu"
      "webnn-npu"
    ]) "ONNX execution provider for local tiny models.";
    tinyModelDtype = mkOpt (t.enum [
      "default"
      "q4"
      "q4f16"
      "q8"
      "fp16"
      "fp32"
      "int8"
      "uint8"
      "bnb4"
      "q2"
      "q2f16"
      "q1"
      "q1f16"
      "auto"
    ]) "ONNX quantization/precision for local tiny models.";
    memoryModel = mkOpt (t.enum tinyMemoryModels) "Mnemopi fact-extraction model: online or a local on-device model.";
    autoThinkingModel = mkOpt (t.enum tinyMemoryModels) "Difficulty classifier for the auto thinking level.";
    kimiApiFormat = mkOpt (t.enum [
      "auto"
      "openai"
      "anthropic"
    ]) "API format for the Kimi Code provider (auto follows live model metadata).";
    openaiWebsockets = mkOpt (t.enum [
      "auto"
      "off"
      "on"
    ]) "WebSocket policy for OpenAI Codex models.";
    openrouterVariant = mkOpt (t.enum [
      "default"
      "nitro"
      "floor"
      "online"
      "exacto"
    ]) "Default routing-variant suffix appended to OpenRouter model ids.";
    fetch = mkOpt (t.enum [
      "auto"
      "native"
      "trafilatura"
      "lynx"
      "parallel"
      "jina"
    ]) "Reader backend priority for the fetch/read URL tool.";
    tts = mkOpt (t.enum [
      "auto"
      "local"
      "xai"
      "deepinfra"
    ]) "Backend for the tts tool: local on-device (Kokoro-82M), xAI Grok Voice, or DeepInfra speech.";
    unexpectedStopModel = mkOpt (t.enum tinyMemoryModels) "Classifier model for unexpected-stop detection.";
    webSearchExclude = mkOpt (t.listOf t.str) "Web-search provider ids to exclude from auto-selection.";
    antigravityEndpoint = mkOpt (t.enum [
      "auto"
      "production"
      "sandbox"
    ]) "Endpoint routing for google-antigravity providers (chat/search/image/discovery).";
    fireworksTier = mkOpt (t.enum [
      "standard"
      "priority"
    ]) "Default Fireworks serving path.";
    maxInFlightRequests = mkOpt (t.attrsOf num) "Max concurrent LLM requests per provider id (e.g. openai, anthropic); omitted providers are unlimited.";
    webSearchGeminiModel = mkOpt t.str "Model id for Gemini Google Search grounding (default gemini-2.5-flash).";
    streamFirstEventTimeoutSeconds = mkOpt num "Seconds to wait for the first model stream event (-1 = provider/env default, 0 = disable watchdog).";
    streamIdleTimeoutSeconds = mkOpt num "Seconds a model stream may stay silent between events (-1 = provider/env default, 0 = disable).";
    autoThinkingMaxEffort =
      mkOpt
        (t.enum [
          "xhigh"
          "max"
        ])
        "Highest effort the `auto` thinking classifier may resolve; xhigh keeps it one tier below the top so only an explicit ultrathink reaches max.";
    cacheRetention =
      mkOpt
        (t.enum [
          "auto"
          "short"
          "long"
          "none"
        ])
        "Prompt-cache retention forwarded to providers that support it (Anthropic, Bedrock, OpenRouter, OpenAI): auto = provider default, short = 5m, long = 1h, none = disable caching and cache-affinity routing.";
    webSearchTimeoutSeconds = mkOpt num "Hard timeout in seconds for each provider's search transport before web_search advances to the next fallback.";
    anthropic = mkSection "Anthropic-specific provider behaviour." {
      serverSideFallback = mkOpt t.bool "Retry safety-classifier-blocked Claude Fable 5 / Mythos 5 requests on Claude Opus 4.8 server-side (beta; opt-in).";
    };
    "ollama-cloud" = mkSection "Ollama Cloud provider limits." {
      maxConcurrency = mkOpt num "Max concurrent Ollama Cloud subagent runs per process (0 disables the limit).";
    };
    "openai-codex" = mkSection "OpenAI Codex provider behaviour." {
      codeMode =
        mkOpt
          (t.enum [
            "off"
            "on"
            "auto"
          ])
          "Route Codex code_mode_only models (GPT-5.6) through eval, mirroring codex-rs Code Mode; auto follows the model catalog flag.";
      codeModeDirectTools = mkOpt (t.listOf t.str) "Extra direct tools for Codex Code Mode; the standard direct tools are eval, ask, todo, yield, think, checkpoint and rewind.";
    };
  };

  provider = mkSection "Cross-provider request behaviour." {
    appendOnlyContext = mkOpt (t.enum [
      "auto"
      "on"
      "off"
    ]) "Cache system prompt + tool specs and keep an append-only message log for prefix caching.";
  };

  exa = mkSection "Exa search tools." {
    enabled = mkOpt t.bool "Master toggle for all Exa search tools.";
    searchDelayMs = mkOpt num "Minimum delay between Exa web-search requests in ms (0 disables pacing).";
  };

  searxng = mkSection "Self-hosted SearXNG search." {
    endpoint = mkOpt t.str "Self-hosted search base URL.";
    token = mkOpt t.str "Optional API token.";
    basicUsername = mkOpt t.str "Optional HTTP basic-auth username.";
    basicPassword = mkOpt t.str "Optional HTTP basic-auth password.";
    categories = mkOpt t.str "Default search categories.";
    language = mkOpt t.str "Default search language.";
    engines = mkOpt t.str "Default comma-separated engine list.";
    safesearch = mkOpt num "Default safesearch level (0 = off, 1 = moderate, 2 = strict).";
  };

  commit = mkSection "Commit changelog generation and caching." {
    mapReduceEnabled = mkOpt t.bool "Enable map-reduce changelog generation for large commits.";
    mapReduceThreshold = mkOpt num "Diff token count above which map-reduce changelog generation kicks in.";
    mapBatchTokenBudget = mkOpt num "Token budget per map-phase batch.";
    cacheEnabled = mkOpt t.bool "Cache generated commit changelogs.";
    cacheTtlDays = mkOpt num "Days a cached commit changelog stays valid.";
    changelogMaxDiffChars = mkOpt num "Maximum diff characters fed into changelog generation.";
  };

  codexResets = mkSection "Codex saved rate-limit reset auto-redeem." {
    autoRedeem = mkOpt (t.enum [
      "unset"
      "yes"
      "no"
    ]) "Whether to auto-redeem saved Codex rate-limit resets.";
    minBlockedMinutes = mkOpt num "Minimum blocked minutes before redeeming a reset.";
    keepCredits = mkOpt num "Credits to keep in reserve when redeeming.";
    salvageHorizonHours = mkOpt num "Spend a saved Codex reset automatically when it would otherwise expire within this many hours and either chat window has meaningful usage to restore (0 disables expiry salvage).";
  };

  tts = mkSection "Local TTS model/voice selection." {
    localModel = mkOpt (t.enum [ "kokoro" ]) "On-device neural TTS model.";
    localVoice = mkOpt (t.enum kokoroVoices) "Kokoro voice used by the local TTS backend.";
  };

  live = mkSection "Codex-backed realtime voice sessions." {
    voice = mkOpt (t.enum liveVoices) "Voice used by Codex-backed realtime voice sessions.";
  };

  speech = mkSection "Spoken assistant output." {
    enabled = mkOpt t.bool "Speak the assistant's output aloud as it streams.";
    mode =
      mkOpt
        (t.enum [
          "all"
          "assistant"
          "yield"
        ])
        "What to speak: all (messages + thinking), assistant (messages only), or yield (final message only).";
    voice = mkOpt (t.enum kokoroVoices) "Kokoro voice used when speaking output aloud.";
    enhanced = mkOpt t.bool "Rewrite assistant output into natural spoken prose with the tiny/smol model before synthesis (falls back to mechanical cleanup).";
  };
}
