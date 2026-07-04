# Opt-in home-manager feature paths. Each value is a path so the consumer's
# module system handles the import (and `inputs`/`pkgs` arrive via its args).
{
  cli = {
    bat = ./cli/bat.nix;
    btop = ./cli/btop.nix;
    direnv = ./cli/direnv.nix;
    fish = ./cli/fish.nix;
    fzf = ./cli/fzf.nix;
    gh = ./cli/gh.nix;
    git = ./cli/git.nix;
    gpg = ./cli/gpg.nix;
    helix = ./cli/helix.nix;
    mcp = ./cli/mcp.nix;
    mise = ./cli/mise;
    mise-oh-my-pi = ./cli/mise/oh-my-pi.nix;
    nix-search-tv = ./cli/nix-search-tv.nix;
    qalculate = ./cli/qalculate.nix;
    ssh = ./cli/ssh.nix;
  };
  desktop = {
    firefox = ./desktop/firefox.nix;
    ghostty = ./desktop/ghostty.nix;
    losslesscut = ./desktop/losslesscut.nix;
    mpv = ./desktop/mpv.nix;
    plasma = ./desktop/plasma.nix;
    vscode = ./desktop/vscode.nix;
  };
  stylix-theme = ./stylix-theme.nix;
}
