# Fish for interactive shells, bash as the login shell.
#
# Leave users.users.<name>.shell at its bash default. Fish only runs a
# non-tty stdin once that stream closes, so tools that drive the login shell
# line by line over stdin (VS Code Remote-SSH) hang when it is fish:
# https://github.com/microsoft/vscode-remote-release/issues/2509
#
# The exec lives in /etc/bashrc's interactive ($PS1) block, so `ssh host cmd`,
# piped stdin and deploy tooling keep plain bash. It is also skipped when the
# parent is fish (an explicit `bash`), for `bash -ic`, and in nix develop /
# nix-shell, whose bash carries the dev environment.
{ config, lib, ... }:
{
  programs.fish.enable = true;

  programs.bash.interactiveShellInit = ''
    if [[ $(< /proc/$PPID/comm) != fish && -z ''${BASH_EXECUTION_STRING:-} && -z ''${IN_NIX_SHELL:-} ]]; then
      shopt -q login_shell && LOGIN_OPTION=--login || LOGIN_OPTION=
      exec ${lib.getExe config.programs.fish.package} $LOGIN_OPTION
    fi
  '';
}
