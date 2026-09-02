# Fish 4.x with the Tide v6 prompt, preconfigured to the Lean preset. The
# preset is shipped declaratively via xdg.configFile so the prompt is fully
# configured on first interactive shell — no `tide configure` round-trip.
{ pkgs, ... }:
{
  programs.fish = {
    enable = true;

    # One derivation per package in home.packages, generated from that
    # package's man pages. They hash on the exact package set, so they are
    # never substitutable and rebuild on every flake input bump.
    generateCompletions = false;

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

    # Tide 6.2 runs the tool binary without checking it exists, so entering a
    # tree with package.json/bun.lockb while node/bun is off PATH (e.g. after
    # leaving a direnv shell that provided it) prints "Unknown command: node"
    # from the async right prompt. Same bodies as upstream plus the
    # `command -q` guard that _tide_item_python already has; ~/.config/fish/
    # functions precedes the plugin dir on fish_function_path, so these shadow
    # it. Drop once upstream guards them.
    functions = {
      _tide_item_node = ''
        if path is $_tide_parent_dirs/package.json; and command -q node
            node --version | string match -qr "v(?<v>.*)"
            _tide_print_item node $tide_node_icon' ' $v
        end
      '';
      _tide_item_bun = ''
        if path is $_tide_parent_dirs/bun.lockb; and command -q bun
            bun --version | string match -qr "(?<v>.*)"
            _tide_print_item bun $tide_bun_icon' ' $v
        end
      '';
    };

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
      ws = "wt switch --execute=omp";
      wsc = "wt switch --create --execute=omp";
    };
  };

  # Tide preset lives in conf.d so it loads at fish startup. The `00-` prefix
  # keeps it ahead of any future tide-shipped conf.d snippets lexically. The
  # preset only sets `tide_*` variables; the prompt functions in tide are
  # autoloaded on first render and read whatever is set at that moment.
  xdg.configFile."fish/conf.d/00-tide-lean.fish".source = ./fish/tide-lean.fish;
}
