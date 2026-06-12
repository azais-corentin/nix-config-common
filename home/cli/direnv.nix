# direnv + nix-direnv hook for `use flake` in per-project devshells.
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
