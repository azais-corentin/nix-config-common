# nix-config-common

Shared NixOS and home-manager modules consumed by
[`nix-config`](https://github.com/azais-corentin/nix-config) (personal) and
[`nix-config-work`](https://github.com/azais-corentin/nix-config-work) (work).

The flake locks `nixpkgs` only for its repo-local dev tooling (`formatter`,
`devShells`). Every module is a plain file evaluated with the **consumer's**
nixpkgs (passed through the module system), so consumers declare
`inputs.nixpkgs.follows = "nixpkgs"` and never lock a second nixpkgs.

## Outputs

| Output                 | Contents                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------- |
| `homeModules`          | `{ oh-my-pi, jcode }` — leaf HM modules, safe to `attrValues`-import.                 |
| `nixosModules`         | `{ desktop, plasma6, stylix-theme }`.                                                 |
| `homeFeatures`         | Nested attrset of opt-in HM feature **paths** (`cli.*`, `desktop.*`, `stylix-theme`). |
| `lib.kwinOutputConfig` | `{ pkgs, outputs, setups }` → generated `kwinoutputconfig.json` derivation.           |
| `formatter`            | `nixfmt` for `x86_64-linux` / `aarch64-linux`.                                        |
| `devShells`            | Dev shell with mise, dprint, nixfmt, gitleaks for the formatting/hook workflow.       |

`homeFeatures` and `lib` are non-standard flake outputs; `nix flake check`
emits a warning about them. This is expected.

## Consumer contract

A consumer that imports the shared features **MUST**:

1. **Add this flake as an input**, following its own nixpkgs:

   ```nix
   nix-config-common = {
     url = "github:azais-corentin/nix-config-common";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. **Declare the flake inputs the shared features reference**:
   - `firefox-addons` — `url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons"`, `inputs.nixpkgs.follows = "nixpkgs"` (used by `homeFeatures.desktop.firefox`).
   - `nix-vscode-extensions` — `url = "github:nix-community/nix-vscode-extensions"`, `inputs.nixpkgs.follows = "nixpkgs"` (used by `homeFeatures.desktop.vscode`).

3. **Apply two overlays** to the consumer's `pkgs`:
   - the `flake-inputs` overlay (surfaces `pkgs.inputs.<flake>.*`, e.g. `pkgs.inputs.firefox-addons`),
   - `inputs.nix-vscode-extensions.overlays.default` (surfaces `pkgs.nix-vscode-extensions.vscode-marketplace.*`).

4. **Ensure the stylix HM module's options exist** in every home that imports
   shared features (so `stylix.*` resolves even when `stylix.enable = false`):
   - work: auto-injected by the stylix **NixOS** module;
   - personal: import `inputs.stylix.homeModules.stylix` in the home globals.

5. **Pass `inputs` to every module** that references
   `inputs.nix-config-common.*` (it arrives via `specialArgs` /
   `extraSpecialArgs` — just add `{ inputs, ... }:` to the module header).

### stylix-theme split

`nixosModules.stylix-theme` and `homeFeatures.stylix-theme` both set the same
palette/fonts via `lib.mkDefault`; neither sets `stylix.enable` or
`stylix.image`. A consumer using stylix's NixOS→HM auto-injection
(`homeManagerIntegration`) must import **only** the NixOS one — the HM values
propagate automatically, and importing both would double-define.

## Development

Formatting and hooks mirror [`nix-config`](https://github.com/azais-corentin/nix-config):
dprint (`.dprint.json`, with `nixfmt` for `.nix` and `pkl format` for `.pkl`),
hk hooks (`hk.pkl`: pre-commit = dprint check + gitleaks + pkl; commit-msg =
conventional-commit lint), mise tasks/tools (`.mise/`).

One-time setup:

```sh
direnv allow            # flake devShell: mise, dprint, nixfmt, gitleaks
mise trust && mise install  # hk/bun/pkl/gitleaks; auto-installs the git hooks
bun install --cwd .mise # commitlint dependencies
```

Run `mise tasks` to list public tasks and `mise run <task> --help` for arguments.

| Command                                     | Purpose                                                                 |
| ------------------------------------------- | ----------------------------------------------------------------------- |
| `mise run check`                            | Check working-tree formatting, Pkl, and secrets without modifying files |
| `mise run check:nix`                        | Evaluate this flake without building or changing its lockfile           |
| `mise run format` / `mise run format:check` | Format with dprint or check formatting only                             |
| `mise run pre-commit`                       | Check staged changes with the existing stashing behavior                |
| `mise run update`                           | Update flake inputs, applications, then agent skills                    |
| `mise run update:inputs nixpkgs`            | Update named flake inputs, or all inputs when omitted                   |
| `mise run update:apps fastpotify mise`      | Update named applications, or all managed applications when omitted     |
| `mise run update:skills anthropics`         | Update named skill sources, or all sources when omitted                 |

`check` does not evaluate Nix, build, fix files, or stash changes. `check:nix`
checks this flake's outputs only. It does not validate modules inside a
consumer's NixOS or Home Manager configuration.
The hidden `commitlint <file>` and `pkl-format` tasks support the hooks and dprint.
Commit messages must follow Conventional Commits.

## Update workflow

Application targets are `fastpotify`, `mise`, and `ff-ultima`.
Fastpotify and mise update their version and both Linux architecture hashes
together.
The `fastpotify` target tracks upstream Spotifast releases.

FF-ULTIMA selects a stable release containing the current commit, or advances
its Git pin when the release is older. Other applications use stable releases.

Skill sources are `anthropics`, `wshobson`, `apollographql`, and `antfu`. Each
target resolves the upstream default-branch commit, verifies the referenced
skill files, and updates all matching OMP and jcode declarations.

Each updater prepares all changes for a target before replacing its files.
A failed target leaves earlier successful targets in place and stops the task.

Updates affect this repository only. They do not install tools, activate
configurations, restart services, commit, or push. They leave tooling dependency
versions, such as commitlint and dprint plugins, alone.

Use `GH_TOKEN` or `GITHUB_TOKEN` for authenticated GitHub API requests if needed.
Source and hash updates do not prove runtime compatibility.

Commit and push validated shared changes before updating a consumer's normal
GitHub input. Then run this command in the consumer repository:

```sh
nix flake update nix-config-common
```
