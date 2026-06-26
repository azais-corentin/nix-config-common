# Fish 4.x with the Tide v6 prompt, preconfigured to the Lean preset. The
# preset is shipped declaratively via xdg.configFile so the prompt is fully
# configured on first interactive shell — no `tide configure` round-trip.
{ pkgs, ... }:
{
  programs.fish = {
    enable = true;

    plugins = [
      {
        name = "tide";
        src = pkgs.fishPlugins.tide.src;
      }
    ];

    # Silence the default greeting; Tide is its own welcome.
    interactiveShellInit = ''
      set fish_greeting
    '';

    # Ported from the previous zsh shellAliases. Abbreviations expand inline
    # in fish so the user sees the resolved command before pressing enter.
    shellAbbrs = {
      ll = "eza -l --git --icons";
      la = "eza -la --git --icons";
      tree = "eza --tree";
      ls = "eza";
      lx = "eza -lbhHigSa@";
      lt = "eza -TgF --git --icons --group-directories-first --time-style=relative --color-scale";
      cat = "bat -p";
      g = "git";
      ".." = "cd ..";
      vi = "hx";
      vim = "hx";
      nano = "hx";
      nrs = "nh os switch";
      nrt = "nh os test";
    };
  };

  # Tide preset lives in conf.d so it loads at fish startup. The `00-` prefix
  # keeps it ahead of any future tide-shipped conf.d snippets lexically. The
  # preset only sets `tide_*` variables; the prompt functions in tide are
  # autoloaded on first render and read whatever is set at that moment.
  xdg.configFile."fish/conf.d/00-tide-lean.fish".source = ./fish/tide-lean.fish;
}
