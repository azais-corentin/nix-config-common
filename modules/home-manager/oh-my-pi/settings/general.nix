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

  extensions = mkOpt (t.listOf t.str) "Explicitly enabled extension ids.";
  enabledModels = mkOpt (t.listOf t.str) "Explicit allow-list of model ids to expose.";
  disabledProviders = mkOpt (t.listOf t.str) "Provider ids to hide.";
  disabledExtensions = mkOpt (t.listOf t.str) "Extension ids to disable.";
  modelProviderOrder = mkOpt (t.listOf t.str) "Preferred ordering of model providers.";
  cycleOrder = mkOpt (t.listOf t.str) "Model-role cycle order (default: smol, default, slow).";

  modelRoles = mkOpt (t.attrsOf t.str) "Role → model-selector map (default, smol, slow, vision, plan, ...).";

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
}
