# `omp-at <spec> [omp args…]`: run oh-my-pi from source at a PR, branch, tag
# or commit (several stacked with `+`), using the local clone. Logic in
# ./omp-at.sh. `nix` stays the system one (talks to the system daemon).
pkgs:
pkgs.writeShellApplication {
  name = "omp-at";
  runtimeInputs = with pkgs; [
    coreutils
    git
    gnutar
    util-linux
  ];
  text = builtins.readFile ./omp-at.sh;
}
