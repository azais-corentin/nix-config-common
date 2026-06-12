# Providers settings: secret handling, web/image/tiny-model provider selection,
# append-only context, Exa, SearXNG and the commit map-reduce knobs.
{ lib, helpers }:
let
  inherit (helpers) mkOpt mkSection num;
  t = lib.types;

  tinyMemoryModels = [
    "online"
    "qwen3-1.7b"
    "gemma-3-1b"
    "qwen2.5-1.5b"
    "lfm2-1.2b"
  ];
in
{
  secrets = mkSection "Secret handling." {
    enabled = mkOpt t.bool "Obfuscate secrets before sending to AI providers.";
  };

  providers = mkSection "Provider selection for built-in tools." {
    webSearch = mkOpt (t.enum [
      "auto"
      "exa"
      "brave"
      "jina"
      "kimi"
      "zai"
      "perplexity"
      "anthropic"
      "gemini"
      "codex"
      "tavily"
      "kagi"
      "synthetic"
      "parallel"
      "searxng"
    ]) "Provider for the web search tool.";
    image = mkOpt (t.enum [
      "auto"
      "openai"
      "antigravity"
      "xai"
      "gemini"
      "openrouter"
    ]) "Provider for the image generation tool.";
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
      "openai"
      "anthropic"
    ]) "API format for the Kimi Code provider.";
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
    enableSearch = mkOpt t.bool "Basic search, deep search, code search, crawl.";
    enableResearcher = mkOpt t.bool "AI-powered deep research tasks.";
    enableWebsets = mkOpt t.bool "Webset management and enrichment tools.";
  };

  searxng = mkSection "Self-hosted SearXNG search." {
    endpoint = mkOpt t.str "Self-hosted search base URL.";
    token = mkOpt t.str "Optional API token.";
    basicUsername = mkOpt t.str "Optional HTTP basic-auth username.";
    basicPassword = mkOpt t.str "Optional HTTP basic-auth password.";
    categories = mkOpt t.str "Default search categories.";
    language = mkOpt t.str "Default search language.";
  };

  commit = mkSection "Commit map-reduce changelog generation." {
    mapReduceEnabled = mkOpt t.bool "Enable map-reduce changelog generation for large commits.";
    mapReduceMinFiles = mkOpt num "Minimum changed files before map-reduce kicks in.";
    mapReduceMaxFileTokens = mkOpt num "Maximum tokens per file in the map phase.";
    mapReduceTimeoutMs = mkOpt num "Map-reduce timeout in milliseconds.";
    mapReduceMaxConcurrency = mkOpt num "Maximum concurrent map workers.";
    changelogMaxDiffChars = mkOpt num "Maximum diff characters fed into changelog generation.";
  };
}
