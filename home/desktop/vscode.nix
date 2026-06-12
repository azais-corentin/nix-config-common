# Shared VS Code base. Extensions sourced from nixpkgs (`pkgs.vscode-extensions`)
# and the marketplace mirror (`pkgs.nix-vscode-extensions.vscode-marketplace`,
# via the consumer's overlay). Theme/language extras live in each consumer's
# layer; `workbench.colorTheme` is mkForce so stylix cannot override it.
{ lib, pkgs, ... }:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscode;
    mutableExtensionsDir = true;

    profiles.default = {
      enableExtensionUpdateCheck = true;
      enableUpdateCheck = true;
      enableMcpIntegration = true;

      extensions =
        (with pkgs.vscode-extensions; [
          jnoortheen.nix-ide
          mkhl.direnv
          ms-vscode.cpptools
          rust-lang.rust-analyzer
          tamasfe.even-better-toml
          usernamehw.errorlens
          vadimcn.vscode-lldb
          ms-python.python
        ])
        ++ (with pkgs.nix-vscode-extensions.vscode-marketplace; [
          monokai.theme-monokai-pro-vscode
          gxl.git-graph-3
          fill-labs.dependi
        ]);

      userSettings = {
        # mkForce beats stylix's normal-priority colorTheme.
        "workbench.colorTheme" = lib.mkForce "Monokai Pro (Filter Spectrum)";
        "workbench.secondarySideBar.defaultVisibility" = "hidden";
        "editor.formatOnSave" = true;
        "editor.inlayHints.enabled" = "offUnlessPressed";
        "direnv.restart.automatic" = true;
        "git.autofetch" = "all";
        "git.confirmSync" = false;
        "git.suggestSmartCommit" = false;
        "git.blame.ignoreWhitespace" = true;
        "git.followTagsWhenSync" = true;
        "git.openRepositoryInParentFolders" = "always";
        "remote.SSH.enableRemoteCommand" = true;
        "diffEditor.renderSideBySide" = true;
        "diffEditor.hideUnchangedRegions.enabled" = true;
        "diffEditor.experimental.showMoves" = true;
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.serverSettings".nixd.formatting.command = [ (lib.getExe pkgs.nixfmt) ];
        "telemetry.telemetryLevel" = "off";
        "update.mode" = "none";
        "scm.defaultViewMode" = "tree";
        "scm.repositories.selectionMode" = "multiple";
        "json.schemaDownload.trustedDomains" = {
          "https://developer.microsoft.com/json-schemas/" = true;
          "https://json-schema.org/" = true;
          "https://json.schemastore.org/" = true;
          "https://plugins.dprint.dev" = true;
          "https://raw.githubusercontent.com/" = true;
          "https://raw.githubusercontent.com/devcontainers/spec/" = true;
          "https://raw.githubusercontent.com/microsoft/vscode/" = true;
          "https://schema.tauri.app" = true;
          "https://schemastore.azurewebsites.net/" = true;
          "https://shadcn-svelte.com" = true;
          "https://www.schemastore.org/" = true;
        };
      };

      keybindings = [
        {
          key = "alt+left";
          command = "workbench.action.navigateBack";
          when = "canNavigateBack";
        }
        {
          key = "alt+right";
          command = "workbench.action.navigateForward";
          when = "canNavigateForward";
        }
      ];
    };
  };
}
