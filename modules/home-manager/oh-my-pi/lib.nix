# Pure helper attrset shared by the oh-my-pi sub-modules. Imported as
# `import ./lib.nix { inherit lib pkgs; }`. Holds the option constructors,
# the null/empty pruner, the YAML/JSON formatters, and the home.file entry
# builders for skills/commands/raw files.
{ lib, pkgs }:
let
  inherit (lib) types;

  yamlFormat = pkgs.formats.yaml { };
  jsonFormat = pkgs.formats.json { };

  # omp `type: "number"` settings are arbitrary JS numbers — some are integer
  # counts/ms, some are floats (thresholds, temperature). Accept either.
  num = types.either types.int types.float;

  # Nullable option that defaults to null, so unset keys are pruned and omp's
  # own upstream default applies. The jcode module uses the same pattern.
  mkOpt =
    type: description:
    lib.mkOption {
      type = types.nullOr type;
      default = null;
      inherit description;
    };

  # A nested object: a submodule whose typed options are merged with a freeform
  # escape hatch (the YAML value type) for forward-compat with new omp keys.
  # Defaults to {} so omitting it prunes cleanly.
  mkSection =
    description: options:
    lib.mkOption {
      type = types.submodule {
        freeformType = yamlFormat.type;
        inherit options;
      };
      default = { };
      inherit description;
    };

  # Submodule *type* (not an option) for list/record element values that carry
  # their own typed fields plus a freeform escape hatch.
  subType =
    options:
    types.submodule {
      freeformType = yamlFormat.type;
      inherit options;
    };

  # Recursively strip `null` values and empty attrsets so the rendered config
  # stays minimal. Lists are walked element-wise but never collapsed when empty
  # (an explicitly-empty list is a meaningful override). Mirrors jcode.
  pruneNulls =
    v:
    if lib.isAttrs v && !(lib.isDerivation v) then
      lib.pipe v [
        (lib.mapAttrs (_: pruneNulls))
        (lib.filterAttrs (_: x: x != null && !(lib.isAttrs x && x == { })))
      ]
    else if lib.isList v then
      map pruneNulls v
    else
      v;

  # Recursively lower the priority of inherited profile declarations while
  # keeping every nested leaf independently overridable. Derivations are
  # leaves: traversing them would rewrite their internal attrs.
  mkDefaultRecursive =
    value:
    if lib.isAttrs value && !(lib.isDerivation value) then
      lib.mapAttrs (_: mkDefaultRecursive) value
    else
      lib.mkDefault value;

  # Canonical OMP profile names, excluding the implicit default sentinel and
  # Windows device basenames that cannot be used portably as directories.
  isValidProfileName =
    name:
    lib.isString name
    && name != "default"
    && !(lib.hasSuffix "." name)
    && builtins.match "^[a-z0-9][a-z0-9._-]{0,63}$" name != null
    && builtins.match "^(con|prn|aux|nul|com[0-9]|lpt[0-9])(\\..*)?$" name == null;

  # ── Skill / file source helpers (reused from the previous oh-my-pi.nix) ────

  # Parse "github:owner/repo/subdir@ref" → { owner, repo, subdir, ref } or null.
  parseGithubRef =
    s:
    let
      m = builtins.match "github:([^/]+)/([^/@]+)(/[^@]*)?@(.+)" s;
    in
    if m == null then
      null
    else
      {
        owner = builtins.elemAt m 0;
        repo = builtins.elemAt m 1;
        subdir =
          let
            raw = builtins.elemAt m 2;
          in
          if raw == null then "" else lib.removePrefix "/" raw;
        ref = builtins.elemAt m 3;
      };

  # 40-char lowercase hex → treat as commit SHA (allows pure eval with `rev`).
  isCommitHash = s: builtins.match "[0-9a-f]{40}" s != null;

  # Fetch a GitHub repo and return the store path to the (optionally nested) subdir.
  fetchGithubSkill =
    {
      owner,
      repo,
      subdir,
      ref,
    }:
    let
      fetched = builtins.fetchGit (
        {
          url = "https://github.com/${owner}/${repo}";
        }
        // (if isCommitHash ref then { rev = ref; } else { inherit ref; })
      );
      base = builtins.toString fetched;
    in
    if subdir != "" then "${base}/${subdir}" else base;

  # Submodule type for structured remote skill sources.
  skillSrcSubmodule = types.submodule {
    options = {
      src = lib.mkOption {
        type = types.either types.path types.str;
        description = "Store path or fetcher result (e.g. pkgs.fetchFromGitHub, builtins.fetchGit, flake input).";
      };
      subdir = lib.mkOption {
        type = types.str;
        default = "";
        description = "Subdirectory within src containing the skill.";
      };
    };
  };

  # Union type covering all skill value forms.
  skillType = types.oneOf [
    types.path
    types.lines
    skillSrcSubmodule
  ];

  # Shared type for extensibility points that accept a path or inline string.
  contentType = types.either types.lines types.path;

  # Maps an attrset of name→(path|string) into home.file entries.
  #   agentDir: target agent directory relative to the home directory
  #   dirPrefix: directory under agentDir (e.g. "commands")
  #   suffix: extension appended to the name (e.g. ".md")
  mkFileEntries =
    agentDir: dirPrefix: suffix: attrs:
    lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${agentDir}/${dirPrefix}/${name}${suffix}" (
        if lib.isPath content then { source = content; } else { text = content; }
      )
    ) attrs;

  # Like mkFileEntries but the attr name is the verbatim filename (extension
  # included) and directory paths are symlinked recursively. For themes/tools/hooks.
  mkRawFileEntries =
    agentDir: dirPrefix: attrs:
    lib.mapAttrs' (
      name: content:
      lib.nameValuePair "${agentDir}/${dirPrefix}/${name}" (
        if lib.isPath content && lib.pathIsDirectory content then
          {
            source = content;
            recursive = true;
          }
        else if lib.isPath content then
          { source = content; }
        else
          { text = content; }
      )
    ) attrs;

  # Skills support directories (with assets), single files, inline strings,
  # github: shorthand refs, and structured { src, subdir } attrsets.
  mkSkillEntries =
    agentDir: attrs:
    lib.mapAttrs' (
      name: content:
      # 1. Nix path to directory → recursive symlink
      if lib.isPath content && lib.pathIsDirectory content then
        lib.nameValuePair "${agentDir}/skills/${name}" {
          source = content;
          recursive = true;
        }
      # 2. Nix path to file → SKILL.md symlink
      else if lib.isPath content then
        lib.nameValuePair "${agentDir}/skills/${name}/SKILL.md" {
          source = content;
        }
      # 3. String: github: shorthand → fetch + recursive symlink
      else if lib.isString content && parseGithubRef content != null then
        lib.nameValuePair "${agentDir}/skills/${name}" {
          source = fetchGithubSkill (parseGithubRef content);
          recursive = true;
        }
      # 4. String: inline SKILL.md content
      else if lib.isString content then
        lib.nameValuePair "${agentDir}/skills/${name}/SKILL.md" {
          text = content;
        }
      # 5. Attrset: structured { src, subdir } → recursive symlink
      else
        lib.nameValuePair "${agentDir}/skills/${name}" {
          source = if content.subdir != "" then "${content.src}/${content.subdir}" else "${content.src}";
          recursive = true;
        }
    ) attrs;
in
{
  inherit
    types
    yamlFormat
    jsonFormat
    num
    mkOpt
    mkSection
    subType
    pruneNulls
    mkDefaultRecursive
    isValidProfileName
    skillType
    contentType
    mkFileEntries
    mkRawFileEntries
    mkSkillEntries
    ;
}
