# oh-my-pi.settings → the selected profile's config.yml
#
# The settings option is a single submodule mapping 1:1 onto the config.yml root:
# top-level scalars are direct options, nested groups are sub-submodules, and a
# freeform escape hatch (YAML value type) accepts any key omp adds later. The
# typed option surface is composed from the per-tab files in ./settings/.
#
# omp reads config.yml via nested path traversal (getByPath), never flat dotted
# keys, so the emitted YAML is nested (e.g. `tools: { xdev: ... }`).
{ lib, pkgs }:
let
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
in
{
  options.settings = lib.mkOption {
    type = lib.types.submodule {
      freeformType = yamlFormat.type;
      options = settingsOptions;
    };
    default = { };
    description = ''
      Typed map of oh-my-pi's config.yml settings written to the selected
      profile's agent directory. Every SETTINGS_SCHEMA key (except the
      runtime-state lastChangelogVersion / setupVersion) is reachable as a
      typed option; unknown keys remain settable via the per-section freeform
      escape hatch.
    '';
  };

  mkFiles =
    {
      agentDir,
      artifactPrefix,
      config,
    }:
    let
      rendered = pruneNulls config.settings;
    in
    lib.optionalAttrs (rendered != { }) {
      "${agentDir}/config.yml".source = yamlFormat.generate "${artifactPrefix}-config.yml" rendered;
    };
}
