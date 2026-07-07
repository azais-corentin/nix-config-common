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

Then `mise run format` / `mise run format:check`, or let the pre-commit hook
enforce it. Commit messages must be conventional commits.

## Update workflow

Edit a shared module here, then:

```sh
git -C ~/dev/nix-config-common commit -am "..." && git push
# in each consumer repo:
nix flake update nix-config-common
```
