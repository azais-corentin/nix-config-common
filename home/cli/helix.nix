# Helix as the system default editor. Theme inherited from stylix where
# enabled. The config.toml onChange hook live-reloads running hx instances.
{ pkgs, lib, ... }:
{
  home.sessionVariables.COLORTERM = "truecolor";

  programs.helix = {
    enable = true;
    defaultEditor = true;
    settings = {
      editor = {
        soft-wrap.enable = true;
        color-modes = true;
        line-number = "absolute";
        bufferline = "multiple";
        indent-guides.render = true;
        cursor-shape = {
          normal = "block";
          insert = "bar";
          select = "underline";
        };
      };
    };
    languages = {
      language = [
        {
          name = "nix";
          language-servers = [
            "nixd"
            "nil"
          ];
          formatter.command = lib.getExe pkgs.nixfmt;
          auto-format = true;
        }
      ];
      language-server = {
        nixd = {
          command = "nixd";
        };
        tinymist = {
          config = {
            typstExtraArgs = [ "main.typ" ];
            exportPdf = "onType";
            outputPath = "$root/$name";
          };
        };
      };
    };
  };
  xdg.configFile."helix/config.toml".onChange = ''
    ${pkgs.procps}/bin/pkill -u $USER -USR1 hx || true
  '';
}
