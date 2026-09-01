# oh-my-pi.models → the selected profile's models.yml
#
# Typed mirror of ModelsConfigSchema (config/models-config-schema.ts): custom
# providers with their models / overrides / compat / discovery. Every submodule
# carries a freeform escape hatch.
{ lib, pkgs }:
let
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
    "bedrock-converse-stream"
    "google-generative-ai"
    "google-gemini-cli"
    "google-vertex"
  ];
  effortEnum = t.enum [
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "max"
  ];
  inputEnum = t.enum [
    "text"
    "image"
  ];

  # RemoteCompactionSchema — per-scope remote compaction endpoint config.
  remoteCompactionType = subType {
    enabled = mkOpt t.bool "Enable remote compaction for this scope.";
    api = mkOpt apiEnum "API variant for the remote compaction endpoint.";
    endpoint = mkOpt t.str "Remote compaction endpoint URL.";
    model = mkOpt t.str "Remote compaction model id.";
    v2StreamingEnabled = mkOpt t.bool "Use the V2 streaming compaction path.";
    v2Endpoint = mkOpt t.str "V2 streaming compaction endpoint URL.";
    streamingEndpoint = mkOpt t.str "Streaming compaction endpoint URL.";
  };

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
    max = mkOpt t.str "Upstream value for the max effort level.";
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
    supportsForcedToolChoice = mkOpt t.bool "Provider supports forcing a specific tool via tool_choice.";
    disableReasoningOnForcedToolChoice = mkOpt t.bool "Disable reasoning when tool choice is forced.";
    disableReasoningOnToolChoice = mkOpt t.bool "Disable reasoning whenever tool_choice is set.";
    thinkingFormat = mkOpt (t.enum [
      "openai"
      "openrouter"
      "zai"
      "qwen"
      "qwen-chat-template"
    ]) "Wire format for thinking content.";
    qwenTemplateReasoningEffort = mkOpt t.bool "Send the chat_template_kwargs.reasoning_effort kwarg; set false to suppress it on strict local OpenAI-compat servers that reject unknown kwargs.";
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
    streamMarkupHealingPattern = mkOpt (t.enum [
      "kimi"
      "dsml"
      "qwen"
      "thinking"
    ]) "Markup-healing pattern applied to malformed streamed tool-call/thinking markup.";
    supportsLongPromptCacheRetention = mkOpt t.bool "Provider supports long prompt cache retention.";
    supportsReasoningParams = mkOpt t.bool "Provider accepts reasoning params.";
    supportsReasoningSummary = mkOpt t.bool "Provider returns reasoning summaries.";
    alwaysSendMaxTokens = mkOpt t.bool "Always include max tokens in the request.";
    strictResponsesPairing = mkOpt t.bool "Enforce strict request/response message pairing (Responses API).";
    supportsImageDetailOriginal = mkOpt t.bool "Provider supports image detail: original.";
    supportsContextManagement = mkOpt t.bool "Provider supports Anthropic context management (anthropic-messages).";
    supportsEagerToolInputStreaming = mkOpt t.bool "Allow Anthropic's per-tool eager_input_streaming flag.";
    allowAnthropicHeaderOverrides = mkOpt t.bool "Allow explicit Anthropic fingerprint headers to replace OAuth defaults on non-official endpoints.";
    requiresToolResultId = mkOpt t.bool "Tool results must carry the tool-use id (anthropic-messages).";
    replayUnsignedThinking = mkOpt t.bool "Replay unsigned thinking blocks (anthropic-messages).";
    promptCacheMode = mkOpt (t.enum [
      "none"
      "automatic"
      "explicit"
    ]) "Bedrock prompt-cache mode.";
    promptCacheMinimumTokens = mkOpt num "Bedrock minimum tokens before prompt caching engages.";
    promptCacheMaximumCheckpoints = mkOpt num "Bedrock maximum prompt-cache checkpoints.";
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
    requiresEffort = mkOpt t.bool "Model requires an effort value; set false to let a supported local model explicitly disable thinking.";
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
    imageInputDecoder = mkOpt (t.enum [ "stb" ]) "Decoder used for image inputs.";
    tokenizer = mkOpt (t.enum [
      "claude-v3"
      "claude-v47"
      "claude-v5"
      "claude-v5-sonnet"
      "qwen3"
      "deepseek-v3"
      "kimi-k2"
      "glm5"
    ]) "Tokenizer used for local token counting.";
    cost = mkOpt costType "Per-token cost.";
    premiumMultiplier = mkOpt num "Premium request multiplier.";
    contextWindow = mkOpt num "Context window size in tokens.";
    maxTokens = mkOpt num "Maximum output tokens.";
    headers = mkOpt (t.attrsOf t.str) "Extra request headers.";
    compat = mkOpt compatType "OpenAI-compat quirk flags.";
    contextPromotionTarget = mkOpt t.str "Model id to promote to on context overflow.";
    omitMaxOutputTokens = mkOpt t.bool "Omit the max-output-tokens field from requests.";
    preferWebsockets = mkOpt t.bool "Prefer the WebSocket transport for this model where available.";
    supportsTools = mkOpt t.bool "Whether the model supports tool calls.";
    compactionModel = mkOpt t.str "Model id used to compact this model's context.";
    remoteCompaction = mkOpt remoteCompactionType "Remote compaction configuration for this model.";
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
    remoteCompaction = mkOpt remoteCompactionType "Remote compaction configuration for this provider.";
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
          "litellm"
        ];
        description = "Model discovery mechanism.";
      };
      timeoutMs = mkOpt num "Discovery request timeout in ms; upstream requires a positive finite number.";
      injectV1 = mkOpt t.bool "Inject /v1 into the discovery model-list URL (default true). Upstream accepts this only when discovery.type = \"openai-models-list\"; set false for gateways rooting their OpenAI-compatible surface at a versioned path.";
    }) "Dynamic model discovery.";
    models = mkOpt (t.listOf modelType) "Explicit model definitions.";
    modelOverrides = mkOpt (t.attrsOf overrideType) "Per-model-id overrides.";
    disableStrictTools = mkOpt t.bool "Disable strict tool schemas for this provider.";
    guardrailIdentifier = mkOpt t.str "Amazon Bedrock Guardrail id or ARN attached to every Converse request under this provider.";
    guardrailVersion = mkOpt t.str "Bedrock guardrail version (upstream defaults to DRAFT when a guardrail is set).";
    guardrailTrace = mkOpt (t.enum [
      "enabled"
      "disabled"
      "enabled_full"
    ]) "Bedrock guardrail trace verbosity.";
    transport = mkOpt (t.enum [
      "pi-native"
    ]) "Streaming transport override (pi-native routes via the auth gateway).";
  };

in
{
  options.models = {
    providers = lib.mkOption {
      type = t.attrsOf providerType;
      default = { };
      description = "Custom model providers written to the selected profile's models.yml.";
    };
  };

  mkFiles =
    {
      agentDir,
      artifactPrefix,
      config,
    }:
    let
      rendered = pruneNulls {
        inherit (config.models) providers;
      };
    in
    lib.optionalAttrs (rendered != { }) {
      "${agentDir}/models.yml".source = yamlFormat.generate "${artifactPrefix}-models.yml" rendered;
    };
}
