# General settings: top-level scalars/arrays/records plus the auth, power and
# marketplace groups. (SETTINGS_SCHEMA general section + scattered top-level keys.)
{ lib, helpers }:
let
  inherit (helpers)
    mkOpt
    mkSection
    subType
    num
    ;
  t = lib.types;
in
{
  autoResume = mkOpt t.bool "Automatically resume the most recent session in the current directory.";
  shellPath = mkOpt t.str "Override the shell binary used for bash tool execution.";

  extensions = mkOpt (t.listOf t.str) "Explicit extension module file or directory paths to load.";
  enabledModels = mkOpt (t.listOf t.str) "Explicit allow-list of model ids to expose.";
  disabledProviders = mkOpt (t.listOf t.str) "Provider ids to hide.";
  enabledProviders = mkOpt (t.listOf t.str) "Explicit allow-list of provider ids to expose.";
  disabledExtensions = mkOpt (t.listOf t.str) "Extension ids to disable.";
  modelProviderOrder = mkOpt (t.listOf t.str) "Preferred ordering of model providers.";
  cycleOrder = mkOpt (t.listOf t.str) "Model-role cycle order (default: smol, default, slow).";

  modelRoleStorage = mkOpt (t.enum [
    "global"
    "project"
  ]) "Where model-role assignments are persisted (upstream default: global).";

  modelRoles =
    mkSection
      ''
        Role → model-selector map. A value is a model selector — `provider/id` or a
        canonical id — with an optional `:level` thinking suffix
        (`:minimal`/`:low`/`:medium`/`:high`/`:xhigh`/`:max`). A role may alias
        another via `@<role>` (`pi/<role>` still accepted as legacy), and a
        comma-separated list forms a fallback chain. Chat roles (`default`, `smol`,
        `slow`, `vision`, `plan`, `commit`, `tiny`, `memory`, `task`, `advisor`)
        resolve against chat models; kind roles (`image`, `web`, `speech`,
        `dictation`, `judge`) resolve against models of the matching kind. Ordered
        fallbacks live in `retry.fallbackChains.<role>`. Custom roles are accepted
        via the freeform escape hatch.
      ''
      {
        default = mkOpt t.str "Primary model for the main agent (DEFAULT role).";
        smol = mkOpt t.str "Fast/cheap model (Fast role); also the fallback chain for the tiny and advisor roles.";
        slow = mkOpt t.str "Strong reasoning model (Thinking role).";
        vision = mkOpt t.str "Vision-capable model used for automatic image description and read's ?q= image questions.";
        plan = mkOpt t.str "Architect model used in plan mode.";
        commit = mkOpt t.str "Model for commit-message and session-title generation.";
        tiny = mkOpt t.str "Lightweight background-task model; accepts tiny on-device models as well as chat models.";
        memory = mkOpt t.str "Memory extraction/consolidation model; accepts tiny on-device models as well as chat models.";
        task = mkOpt t.str "Model for spawned task/subtask subagents.";
        advisor = mkOpt t.str "Passive per-turn reviewer model (only active when advisor.enabled is set).";
        image = mkOpt t.str "Image-generation model backing the generate_image tool.";
        web = mkOpt t.str "Web-search model or web/<provider> backend used by the web_search tool.";
        speech = mkOpt t.str "Text-to-speech model used by the tts tool and spoken output.";
        dictation = mkOpt t.str "Speech-to-text model used for microphone dictation.";
        judge = mkOpt t.str "Judge model used by eval's judge()/judge_batch(), the jevify keyword and the find tool.";
      };

  modelTags = mkOpt (t.attrsOf (subType {
    name = lib.mkOption {
      type = t.str;
      description = "Display name for the tag.";
    };
    color = mkOpt t.str "Optional tag color.";
  })) "Custom model tags keyed by model id.";

  auth = mkSection "Auth broker — credentials proxied through a remote omp auth-broker host." {
    broker = mkSection "Remote auth-broker connection." {
      url = mkOpt t.str "Auth-broker URL (env OMP_AUTH_BROKER_URL takes precedence).";
      token = mkOpt t.str "Auth-broker bearer token (env OMP_AUTH_BROKER_TOKEN takes precedence).";
    };
  };

  power = mkSection "macOS sleep prevention (caffeinate); no-op on other platforms." {
    sleepPrevention =
      mkOpt
        (t.enum [
          "off"
          "idle"
          "display"
          "system"
        ])
        "Prevent macOS sleep during active sessions; levels are cumulative (off < idle < display < system).";
  };

  marketplace = mkSection "Plugin marketplace behaviour." {
    autoUpdate = mkOpt (t.enum [
      "off"
      "notify"
      "auto"
    ]) "Check for plugin updates on startup (off/notify/auto).";
  };

  gc = mkSection "Session-store garbage collection (omp gc defaults)." {
    blobs = mkOpt t.bool "Sweep unreferenced blobs during gc.";
    archive = mkOpt t.bool "Archive cold sessions during gc.";
    wal = mkOpt t.bool "Checkpoint history/model database WAL files during gc.";
    coldArchiveAfterDays = mkOpt num "Minimum session age in days before archiving.";
    retainNewestGlobal = mkOpt num "Always keep this many newest sessions active.";
    retainNewestPerCwd = mkOpt num "Always keep this many newest sessions per cwd active.";
  };

  workspace = mkSection "Multi-root workspace." {
    additionalDirectories = mkOpt (t.listOf t.str) "Extra workspace directories added to every session as additional roots.";
  };
}
