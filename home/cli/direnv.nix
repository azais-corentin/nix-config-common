# direnv + nix-direnv hook for `use flake` in per-project devshells.
{ config, lib, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    # direnv's own default status format, spelled out. The value changes nothing;
    # the point is that a direnv.toml exists, because direnv 2.36+ reads
    # DIRENV_LOG_FORMAT from the environment only when it found one (the lookup
    # sits inside `if config.TomlPath != ""` in internal/cmd/config.go). Without
    # the file, the per-project silencing below is a no-op.
    config.global.log_format = "direnv: %s";
  };

  # Projects whose .envrc carries a `# direnv: quiet` comment load without any
  # direnv log lines; everything else keeps them.
  xdg.configFile."fish/conf.d/10-direnv-quiet.fish" = lib.mkIf config.programs.fish.enable {
    source = ./fish/direnv-quiet.fish;
  };
}
