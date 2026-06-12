# oh-my-pi.settings → ~/.omp/agent/config.yml
#
# The settings option is a single submodule mapping 1:1 onto the config.yml root:
# top-level scalars are direct options, nested groups are sub-submodules, and a
# freeform escape hatch (YAML value type) accepts any key omp adds later. The
# typed option surface is composed from the per-tab files in ./settings/.
#
# omp reads config.yml via nested path traversal (getByPath), never flat dotted
# keys, so the emitted YAML is nested (e.g. `tools: { discoveryMode: ... }`).
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.oh-my-pi;
  helpers = import ./lib.nix { inherit lib pkgs; };
  inherit (helpers) yamlFormat pruneNulls;

  # Compose the typed option surface from the per-tab files. Top-level keys are
  # disjoint across files, so // merges them into one options set.
  args = { inherit lib helpers; };
  settingsOptions = lib.foldl' (acc: f: acc // (import f args)) { } [
    ./settings/general.nix
    ./settings/appearance.nix
    ./settings/model.nix
    ./settings/interaction.nix
    ./settings/context.nix
    ./settings/memory.nix
    ./settings/editing.nix
    ./settings/tools.nix
    ./settings/tasks.nix
    ./settings/providers.nix
  ];

  raw = cfg.settings;

  # ── Nested boolean-vs-subkey collisions ──────────────────────────────────
  # config.yml cannot hold both a scalar `X` and an object `X.Y` at the same
  # nested path. omp treats any object at `X` as truthy (feature on) and reads
  # `X.Y` only then. So: when the sub-value is set, emit `X = { Y = sub; }`;
  # otherwise fall back to the boolean toggle (or null → pruned).

  # todo.reminders (bool) vs todo.reminders.max (number)
  todoFixed =
    let
      td = raw.todo;
    in
    (removeAttrs td [ "reminderMax" ])
    // {
      reminders = if td.reminderMax != null then { max = td.reminderMax; } else td.reminders;
    };

  # dev.autoqa (bool) vs dev.autoqa.consent (enum)
  devFixed =
    let
      dv = raw.dev;
    in
    (removeAttrs dv [ "autoqaConsent" ])
    // {
      autoqa = if dv.autoqaConsent != null then { consent = dv.autoqaConsent; } else dv.autoqa;
    };

  rendered = pruneNulls (
    raw
    // {
      todo = todoFixed;
      dev = devFixed;
    }
  );
in
{
  options.oh-my-pi.settings = lib.mkOption {
    type = lib.types.submodule {
      freeformType = yamlFormat.type;
      options = settingsOptions;
    };
    default = { };
    description = ''
      Typed map of oh-my-pi's config.yml settings written to ~/.omp/agent/config.yml.
      Every SETTINGS_SCHEMA key (except the runtime-state lastChangelogVersion /
      setupVersion) is reachable as a typed option; unknown keys remain settable
      via the per-section freeform escape hatch.
    '';
  };

  config = lib.mkIf (cfg.enable && rendered != { }) {
    home.file.".omp/agent/config.yml".source = yamlFormat.generate "omp-config.yml" rendered;
  };
}
