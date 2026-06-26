# OpenSSH client with connection multiplexing.
#
# We opt out of `programs.ssh`'s legacy default block (which is being
# removed by home-manager) and declare every value we want under
# `programs.ssh.settings."*"`. The non-multiplexing values mirror the
# upstream defaults so behaviour is preserved.
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings."*" = {
      ControlMaster = "auto";
      ControlPersist = "10m";
      ControlPath = "~/.ssh/master-%r@%n:%p";

      # Previously implicit via `enableDefaultConfig`; kept verbatim so
      # behaviour stays identical across the HM 26.05 migration.
      ForwardAgent = false;
      AddKeysToAgent = "no";
      Compression = false;
      ServerAliveInterval = 0;
      ServerAliveCountMax = 3;
      HashKnownHosts = false;
      UserKnownHostsFile = "~/.ssh/known_hosts";
    };

    matchBlocks = {
      # Example host — replace or extend.
      # "example" = {
      #   hostname = "example.com";
      #   user = "nelieru";
      # };
    };
  };
}
