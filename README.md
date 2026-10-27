# nix-config-common

Shared NixOS and home-manager modules consumed by
[`nix-config`](https://github.com/azais-corentin/nix-config) (personal) and
[`nix-config-work`](https://github.com/azais-corentin/nix-config-work) (work).

The flake locks `nixpkgs` only for its repo-local dev tooling and tests
(`formatter`, `devShells`, `checks`). Every module is a plain file evaluated with the **consumer's**
nixpkgs (passed through the module system), so consumers declare
`inputs.nixpkgs.follows = "nixpkgs"` and never lock a second nixpkgs.

## Outputs

| Output                 | Contents                                                                                                                                                       |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `homeModules`          | `{ oh-my-pi }` — leaf HM modules, safe to `attrValues`-import.                                                                                                 |
| `nixosModules`         | `{ desktop, plasma6, stylix-theme, pipewire, docker, bluetooth, dconf, codex, v4l2loopback }`.                                                                 |
| `homeFeatures`         | Nested attrset of opt-in HM feature **paths** (`cli.*`, `desktop.*`, `stylix-theme`); `desktop.ghostty` is a module closing over this flake's `ghostty` input. |
| `lib.kwinOutputConfig` | `{ pkgs, outputs, setups }` → generated `kwinoutputconfig.json` derivation.                                                                                    |
| `lib.mkDevShell`       | `{ pkgs, packages ? [ ], inPlace ? false, ... }` → dev shell with mise, dprint, nixfmt, gitleaks and the `.tooling` link.                                      |
| `formatter`            | `nixfmt` for `x86_64-linux` / `aarch64-linux`.                                                                                                                 |
| `devShells`            | This repo's `lib.mkDevShell` shell (links `tooling/node_modules`, adds nodejs).                                                                                |
| `checks`               | `oh-my-pi` module tests for `x86_64-linux` / `aarch64-linux`.                                                                                                  |

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
   - `claude-usage-estimator` — `url = "git+https://github.com/azais-corentin/claude-usage-estimator"` (private: git+https uses git's credentials), `inputs.nixpkgs.follows = "nixpkgs"` (used by `homeFeatures.cli.claude-usage-estimator`).
   - `firefox-addons` — `url = "git+https://gitlab.com/rycee/nur-expressions.git?dir=pkgs/firefox-addons&shallow=1"` (not `gitlab:`: GitLab's API answers Nix with a Cloudflare 403), `inputs.nixpkgs.follows = "nixpkgs"` (used by `homeFeatures.desktop.firefox`).
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

6. **Import the plasma-manager HM module**
   (`inputs.plasma-manager.homeModules.plasma-manager`) in every home that
   imports `homeFeatures.desktop.plasma` (work: via `home-manager.sharedModules`).

7. **Use `lib.mkDevShell` and the `.tooling` stubs** for shared dev tooling:
   `hk.pkl` (`amends "./.tooling/hk/base.pkl"`), `.dprint.json`
   (`{ "extends": ".tooling/dprint/base.json" }`), `.mise/config.toml`
   (`[task_config] includes = [".tooling/tasks", ".tooling/consumer/tasks", ".mise/tasks"]`),
   and `/.tooling` in `.gitignore`.

### stylix-theme split

`nixosModules.stylix-theme` and `homeFeatures.stylix-theme` both set the same
palette/fonts via `lib.mkDefault`; neither sets `stylix.enable` or
`stylix.image`. A consumer using stylix's NixOS→HM auto-injection
(`homeManagerIntegration`) must import **only** the NixOS one — the HM values
propagate automatically, and importing both would double-define.

### oh-my-pi model presets

`homeFeatures.cli.mise-oh-my-pi` provides `claude`, `gpt`, `gemini`, `deepseek`,
and `muse` presets. Select one with `/modelpreset switch <name>`.
The `muse` preset assigns every role, including `image` and `web`, to
`opencode-go/muse-spark-1.3-contributor`, without a thinking-level override.
Rebuilding restores the startup `claude` roles; adding a preset does not select it.

### Ghostty

`homeFeatures.desktop.ghostty` builds Ghostty's main branch from this flake's
`ghostty` input, against the consumer's nixpkgs (it follows this flake's
`nixpkgs`, which consumers point at theirs), plus a local patch silencing GTK's
`color_change` logs. Consumers declare nothing extra. To move Ghostty, run
`nix flake update ghostty` here, push, then `mise run update:common` in each
consumer.

### Tern

`homeFeatures.desktop.tern` installs Tern beside Ghostty, with a `tern-daemon`
user service and a read-only `~/.config/tern/settings.json` (auto-update off,
stylix's monospace font). The daemon is wanted by `default.target`, so it
starts at boot only when the consumer enables lingering
(`users.users.<name>.linger = true`), and otherwise at the user's first login.
Panes inherit the daemon's display variables. At graphical login,
`tern-daemon-adopt` restarts the daemon into the session's display, unless a
pane is running a program. omp stays mise's: a missing omp state file is seeded
as declined, so Tern never offers to install or manage omp. The Linux archive
is invite-only, so the package uses `requireFile`. Sign in at
<https://build.stencil.so/tern> in Firefox's default
profile, then run `mise run tern:fetch` in the consumer before its first build
and after each Tern version bump. The task adds the archive pinned by the locked
`nix-config-common` to the store, using the Firefox session cookie.

## Development

Formatting, hooks and generic tasks live in `tooling/`, shared with consumers
through `lib.mkDevShell` (which links the locked bundle as `.tooling`):

- `tooling/dprint/base.json`: dprint, with `nixfmt` for `.nix` and `pkl format` for `.pkl`;
- `tooling/hk/base.pkl`: hk hooks (pre-commit = dprint check + gitleaks + pkl;
  commit-msg = conventional-commit lint);
- `tooling/tasks/`: `check`, `format`, `format:check`, `pre-commit`,
  `commitlint`, `pkl-format`, `update:inputs`; `tooling/consumer/tasks/`: `update:workflows`;
- `tooling/lib/update.ts`: the updater library used by every `update:*` task;
- `tooling/lib/report.ts`: their shared output — one `task  N updated, N current`
  line per task, then only what changed as `old → new`, coloured like `nh`;
- `tooling/package.json` / `package-lock.json`: commitlint, built offline by Nix
  (`importNpmLock`) into the bundle's `node_modules`.

The root `hk.pkl`, `.dprint.json` and `.mise/config.toml` are thin stubs over
`tooling/`. This repo's dev shell links `tooling/node_modules` in place.

One-time setup:

```sh
direnv allow                # dev shell: mise, dprint, nixfmt, gitleaks, tooling/node_modules
mise trust && mise install  # hk/bun/pkl; auto-installs the git hooks
```

After editing `tooling/package.json`, regenerate the lockfile in one command
line (npm writes into `node_modules`, which the dev shell links read-only into
the store and re-links on the next prompt; `tooling/.npmrc` keeps peers out):

```sh
rm tooling/node_modules && npm --prefix tooling install --package-lock-only
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
| `mise run update:apps spotifast mise`       | Update named applications, or all managed applications when omitted     |
| `mise run update:skills anthropics`         | Update named skill sources, or all sources when omitted                 |
| `mise run tern:fetch`                       | Add the pinned Tern archive to the Nix store (needs a Firefox sign-in)  |

`check` does not evaluate Nix, build, fix files, or stash changes. `check:nix`
checks this flake's outputs only. It does not validate modules inside a
consumer's NixOS or Home Manager configuration.
The hidden `commitlint <file>` and `pkl-format` tasks support the hooks and dprint.
Commit messages must follow Conventional Commits.

## Update workflow

Application targets are `spotifast`, `mise`, `ff-ultima`, and `tern`.
Spotifast and mise update their version and both Linux architecture hashes
together. `tern` reads Stencil's build list with the Firefox session cookie,
pins the latest stable x86_64 archive by its published SHA-256, and adds it to
this machine's store.

FF-ULTIMA selects a stable release containing the current commit, or advances
its Git pin when the release is older. Other applications use stable releases.

Skill sources are `anthropics`, `wshobson`, `apollographql`, and `antfu`. Each
target resolves the upstream default-branch commit, prefetches its source
archive, verifies every referenced `SKILL.md`, and updates the source's `rev`
and `hash` in `home/cli/mise/oh-my-pi.nix`.

Each updater prepares all changes for a target before replacing its files.
A failed target leaves earlier successful targets in place and stops the task.

Updates affect this repository only. They do not install tools, activate
configurations, restart services, commit, or push. They leave tooling dependency
versions, such as commitlint (`tooling/package-lock.json`) and dprint plugins, alone.

GitHub API requests and nix's `github:` fetches authenticate with `GH_TOKEN` or
`GITHUB_TOKEN`, else with the account logged in to `gh` (`gh auth token`).
Source and hash updates do not prove runtime compatibility.

Commit and push validated shared changes before updating a consumer's normal
GitHub input. Then run this command in the consumer repository:

```sh
nix flake update nix-config-common
```
