# oh-my-pi.models → ~/.omp/agent/models.yml
#
# Typed mirror of ModelsConfigSchema (config/models-config-schema.ts): custom
# providers with their models / overrides / compat / discovery, plus the model
# equivalence map. Every submodule carries a freeform escape hatch.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.oh-my-pi;
  helpers = import ./lib.nix { inherit lib pkgs; };
  inherit (helpers)
    mkOpt
    subType
    num
    yamlFormat
    pruneNulls
    ;
  t = lib.types;

  # Shared enums.
  apiEnum = t.enum [
    "openai-completions"
    "openai-responses"
    "openai-codex-responses"
    "azure-openai-responses"
    "anthropic-messages"
    "google-generative-ai"
    "google-vertex"
  ];
  effortEnum = t.enum [
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
  ];
  inputEnum = t.enum [
    "text"
    "image"
  ];

  routingType = subType {
    only = mkOpt (t.listOf t.str) "Allow-list of upstream providers.";
    order = mkOpt (t.listOf t.str) "Preferred ordering of upstream providers.";
  };

  # ReasoningEffortMapSchema — shared by compat and thinking.
  reasoningEffortMapType = subType {
    minimal = mkOpt t.str "Upstream value for the minimal effort level.";
    low = mkOpt t.str "Upstream value for the low effort level.";
    medium = mkOpt t.str "Upstream value for the medium effort level.";
    high = mkOpt t.str "Upstream value for the high effort level.";
    xhigh = mkOpt t.str "Upstream value for the xhigh effort level.";
  };

  # OpenAICompatFieldsSchema — provider/model quirk flags.
  compatFields = {
    supportsStore = mkOpt t.bool "Provider supports the Responses `store` flag.";
    supportsDeveloperRole = mkOpt t.bool "Provider supports the developer role.";
    supportsMultipleSystemMessages = mkOpt t.bool "Provider accepts multiple system messages.";
    supportsReasoningEffort = mkOpt t.bool "Provider honours reasoning_effort.";
    reasoningEffortMap = mkOpt reasoningEffortMapType "Map effort levels to upstream reasoning values.";
    maxTokensField = mkOpt (t.enum [
      "max_completion_tokens"
      "max_tokens"
    ]) "Field name used to cap output tokens.";
    supportsUsageInStreaming = mkOpt t.bool "Provider reports usage during streaming.";
    requiresToolResultName = mkOpt t.bool "Tool results must carry the tool name.";
    requiresMistralToolIds = mkOpt t.bool "Tool ids must follow the Mistral format.";
    requiresAssistantAfterToolResult = mkOpt t.bool "An assistant message must follow each tool result.";
    requiresThinkingAsText = mkOpt t.bool "Thinking must be sent as plain text.";
    reasoningContentField = mkOpt (t.enum [
      "reasoning_content"
      "reasoning"
      "reasoning_text"
    ]) "Field carrying reasoning content.";
    requiresReasoningContentForToolCalls = mkOpt t.bool "Tool calls must include reasoning content.";
    allowsSyntheticReasoningContentForToolCalls = mkOpt t.bool "Synthetic reasoning content is allowed for tool calls.";
    requiresAssistantContentForToolCalls = mkOpt t.bool "Tool calls must include assistant content.";
    supportsToolChoice = mkOpt t.bool "Provider supports tool_choice.";
    disableReasoningOnForcedToolChoice = mkOpt t.bool "Disable reasoning when tool choice is forced.";
    disableReasoningOnToolChoice = mkOpt t.bool "Disable reasoning whenever tool_choice is set.";
    thinkingFormat = mkOpt (t.enum [
      "openai"
      "openrouter"
      "zai"
      "qwen"
      "qwen-chat-template"
    ]) "Wire format for thinking content.";
    openRouterRouting = mkOpt routingType "OpenRouter provider routing.";
    vercelGatewayRouting = mkOpt routingType "Vercel AI Gateway provider routing.";
    extraBody = mkOpt yamlFormat.type "Extra fields merged into the request body.";
    supportsStrictMode = mkOpt t.bool "Provider supports strict tool schemas.";
    toolStrictMode = mkOpt (t.enum [
      "all_strict"
      "none"
    ]) "Strict-mode policy for tool schemas.";
    cacheControlFormat = mkOpt (t.enum [ "anthropic" ]) "Cache-control wire format.";
    streamIdleTimeoutMs = mkOpt num "Abort the stream after this many ms of idle (must be positive).";
    supportsLongPromptCacheRetention = mkOpt t.bool "Provider supports long prompt cache retention.";
    supportsReasoningParams = mkOpt t.bool "Provider accepts reasoning params.";
    alwaysSendMaxTokens = mkOpt t.bool "Always include max tokens in the request.";
    strictResponsesPairing = mkOpt t.bool "Enforce strict request/response message pairing (Responses API).";
    requiresToolResultId = mkOpt t.bool "Tool results must carry the tool-use id (anthropic-messages).";
    replayUnsignedThinking = mkOpt t.bool "Replay unsigned thinking blocks (anthropic-messages).";
  };

  # OpenAICompatSchema — fields plus thinking-only overrides.
  compatType = subType (
    compatFields
    // {
      whenThinking = mkOpt (subType compatFields) "Compat overrides applied only while thinking is active.";
    }
  );

  thinkingType = subType {
    minLevel = mkOpt effortEnum "Legacy minimum thinking level (use efforts).";
    maxLevel = mkOpt effortEnum "Legacy maximum thinking level (use efforts).";
    mode = lib.mkOption {
      type = t.enum [
        "effort"
        "budget"
        "google-level"
        "anthropic-adaptive"
        "anthropic-budget-effort"
      ];
      description = "Thinking control mode.";
    };
    defaultLevel = mkOpt effortEnum "Default thinking level.";
    levels = mkOpt (t.listOf effortEnum) "Allowed thinking levels.";
    efforts = mkOpt (t.listOf effortEnum) "Ordered allowed thinking efforts (canonical; replaces minLevel/maxLevel/levels).";
    effortMap = mkOpt reasoningEffortMapType "Map effort levels to upstream reasoning values.";
    supportsDisplay = mkOpt t.bool "Model surfaces reasoning display output.";
  };

  # Cost block: required fields on a full model definition.
  modelCostType = t.submodule {
    options = {
      input = lib.mkOption {
        type = num;
        description = "Input token cost.";
      };
      output = lib.mkOption {
        type = num;
        description = "Output token cost.";
      };
      cacheRead = lib.mkOption {
        type = num;
        description = "Cache-read token cost.";
      };
      cacheWrite = lib.mkOption {
        type = num;
        description = "Cache-write token cost.";
      };
    };
  };

  # Cost block on an override: all fields optional.
  overrideCostType = subType {
    input = mkOpt num "Input token cost.";
    output = mkOpt num "Output token cost.";
    cacheRead = mkOpt num "Cache-read token cost.";
    cacheWrite = mkOpt num "Cache-write token cost.";
  };

  # Fields shared by model definitions and overrides.
  sharedModelOptions = costType: {
    name = mkOpt t.str "Display name.";
    reasoning = mkOpt t.bool "Whether the model reasons.";
    thinking = mkOpt thinkingType "Thinking control configuration.";
    input = mkOpt (t.listOf inputEnum) "Accepted input modalities.";
    cost = mkOpt costType "Per-token cost.";
    premiumMultiplier = mkOpt num "Premium request multiplier.";
    contextWindow = mkOpt num "Context window size in tokens.";
    maxTokens = mkOpt num "Maximum output tokens.";
    headers = mkOpt (t.attrsOf t.str) "Extra request headers.";
    compat = mkOpt compatType "OpenAI-compat quirk flags.";
    contextPromotionTarget = mkOpt t.str "Model id to promote to on context overflow.";
    omitMaxOutputTokens = mkOpt t.bool "Omit the max-output-tokens field from requests.";
  };

  modelType = subType (
    sharedModelOptions modelCostType
    // {
      id = lib.mkOption {
        type = t.str;
        description = "Model identifier as sent to the provider (required).";
      };
      api = mkOpt apiEnum "API variant for this model.";
      baseUrl = mkOpt t.str "Per-model base URL override.";
    }
  );

  overrideType = subType (sharedModelOptions overrideCostType);

  providerType = subType {
    baseUrl = mkOpt t.str "Provider base URL.";
    apiKey = mkOpt t.str "API key, or the name of an env var holding it.";
    api = mkOpt apiEnum "API variant for this provider.";
    headers = mkOpt (t.attrsOf t.str) "Extra request headers.";
    compat = mkOpt compatType "OpenAI-compat quirk flags.";
    authHeader = mkOpt t.bool "Send the key in a custom auth header.";
    auth = mkOpt (t.enum [
      "apiKey"
      "none"
      "oauth"
    ]) "Authentication scheme.";
    discovery = mkOpt (subType {
      type = lib.mkOption {
        type = t.enum [
          "ollama"
          "llama.cpp"
          "lm-studio"
          "openai-models-list"
          "proxy"
        ];
        description = "Model discovery mechanism.";
      };
    }) "Dynamic model discovery.";
    models = mkOpt (t.listOf modelType) "Explicit model definitions.";
    modelOverrides = mkOpt (t.attrsOf overrideType) "Per-model-id overrides.";
    disableStrictTools = mkOpt t.bool "Disable strict tool schemas for this provider.";
    transport = mkOpt (t.enum [
      "pi-native"
    ]) "Streaming transport override (pi-native routes via the auth gateway).";
  };

  rendered = pruneNulls {
    inherit (cfg.models) providers equivalence;
  };
in
{
  options.oh-my-pi.models = {
    providers = lib.mkOption {
      type = t.attrsOf providerType;
      default = { };
      description = "Custom model providers written to ~/.omp/agent/models.yml.";
    };
    equivalence = lib.mkOption {
      type = subType {
        overrides = mkOpt (t.attrsOf t.str) "Map a model id to its canonical equivalent.";
        exclude = mkOpt (t.listOf t.str) "Model ids excluded from equivalence grouping.";
      };
      default = { };
      description = "Model equivalence configuration written to ~/.omp/agent/models.yml.";
    };
  };

  config = lib.mkIf (cfg.enable && rendered != { }) {
    home.file.".omp/agent/models.yml".source = yamlFormat.generate "omp-models.yml" rendered;
  };
}
