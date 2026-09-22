# OpenAI Codex CLI. The registry shorthand `codex` resolves to
# aqua:openai/codex — the static musl release binary, which needs no nix-ld.
#
# The `[features]` block that turns on experimental context management is NOT
# here: it ships as /etc/codex/config.toml from nixosModules.codex. Codex
# rewrites $CODEX_HOME/config.toml itself (project trust levels, TUI state), so
# that file cannot be a home-manager symlink; /etc/codex/config.toml is codex's
# lowest-precedence layer, which keeps the user's own file authoritative.
{
  imports = [ ./. ];

  programs.mise.globalConfig.tools.codex = "latest";

  # mise's built-in minimum_release_age default of 24h would hold `latest` a
  # day behind upstream. Codex ships several releases a day and the feature
  # flags tracked in /etc/codex/config.toml follow those releases, so opt codex
  # out of the delay (same treatment as github:can1357/oh-my-pi). List
  # definitions from sibling modules concatenate.
  programs.mise.globalConfig.settings.minimum_release_age_excludes = [ "codex" ];
}
