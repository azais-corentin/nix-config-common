{
  pkgs,
  lib,
  config,
  ...
}:
let
  ultimaTheme = pkgs.fetchFromGitHub {
    owner = "soulhotel";
    repo = "FF-ULTIMA";
    rev = "299811dc2d4ffe898bc3de43d26bff8b9b03e05c";
    sha256 = "sha256-9nEtNmarNRDlz3nzYJDPQ1zLw4KEzD5I/TQjSoz+foE=";
  };

  sharedExtensions = with pkgs.inputs.firefox-addons; [
    ublock-origin
    sponsorblock
    bitwarden
  ];

  sharedSearch = {
    force = true;
    default = "google";
    privateDefault = "google";
    order = [ "google" ];
    engines = {
      "bing".metaData.hidden = true;
    };
  };

  sharedSettings = {
    # === Startup & Homepage ===
    "browser.startup.homepage" = "about:home";
    "browser.startup.homepage_override.mstone" = "ignore";
    "startup.homepage_override_url" = "";

    # === First-Run & Onboarding ===
    "browser.disableResetPrompt" = true;
    "browser.feeds.showFirstRunUI" = false;
    "browser.messaging-system.whatsNewPanel.enabled" = false;
    "browser.rights.3.shown" = true;
    "browser.shell.checkDefaultBrowser" = false;
    "browser.shell.defaultBrowserCheckCount" = 1;
    "browser.uitour.enabled" = false;
    "browser.bookmarks.restore_default_bookmarks" = false;
    "browser.bookmarks.addedImportButton" = true;
    "trailhead.firstrun.didSeeAboutWelcome" = true;

    # === Downloads ===
    "browser.download.panel.shown" = true;
    "browser.download.useDownloadDir" = false;

    # === New Tab Page ===
    "browser.newtabpage.activity-stream.feeds.topsites" = false;
    "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
    "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts" = false;
    "browser.newtabpage.blocked" = lib.genAttrs [
      "26UbzFJ7qT9/4DhodHKA1Q==" # Youtube
      "4gPpjkxgZzXPVtuEoAL9Ig==" # Facebook
      "eV8/WsSLxHadrTL1gAxhug==" # Wikipedia
      "gLv0ja2RYVgxKdp0I5qwvA==" # Reddit
      "K00ILysCaEq8+bEqV/3nuw==" # Amazon
      "T9nJot5PurhJSy8n038xGA==" # Twitter
    ] (_: 1);

    # === Telemetry ===
    "app.shield.optoutstudies.enabled" = false;
    "browser.discovery.enabled" = false;
    "browser.newtabpage.activity-stream.feeds.telemetry" = false;
    "browser.newtabpage.activity-stream.telemetry" = false;
    "browser.ping-centre.telemetry" = false;
    "datareporting.healthreport.service.enabled" = false;
    "datareporting.healthreport.uploadEnabled" = false;
    "datareporting.policy.dataSubmissionEnabled" = false;
    "datareporting.sessions.current.clean" = true;
    "devtools.onboarding.telemetry.logged" = false;
    "toolkit.telemetry.archive.enabled" = false;
    "toolkit.telemetry.bhrPing.enabled" = false;
    "toolkit.telemetry.enabled" = false;
    "toolkit.telemetry.firstShutdownPing.enabled" = false;
    "toolkit.telemetry.hybridContent.enabled" = false;
    "toolkit.telemetry.newProfilePing.enabled" = false;
    "toolkit.telemetry.prompted" = 2;
    "toolkit.telemetry.rejected" = true;
    "toolkit.telemetry.reportingpolicy.firstRun" = false;
    "toolkit.telemetry.server" = "";
    "toolkit.telemetry.shutdownPingSender.enabled" = false;
    "toolkit.telemetry.unified" = false;
    "toolkit.telemetry.unifiedIsOptIn" = false;
    "toolkit.telemetry.updatePing.enabled" = false;

    # === Privacy & Security ===
    "privacy.trackingprotection.enabled" = true;
    "dom.security.https_only_mode" = true;

    # === Accounts & Passwords ===
    "identity.fxaccounts.enabled" = true;
    "signon.rememberSignons" = false;

    # === Sidebar & Tabs ===
    "sidebar.revamp" = false;
    "sidebar.verticalTabs" = false;
    "sidebar.main.tools" = [
      "history"
      "bookmarks"
    ];
    "browser.tabs.splitView.enabled" = true;

    # === UI Layout & Customization ===
    "browser.tabs.inTitlebar" = 0;
    "browser.uiCustomization.state" = builtins.toJSON {
      placements = {
        unified-extensions-area = [ ];
        widget-overflow-fixed-list = [ ];
        nav-bar = [
          "back-button"
          "forward-button"
          "stop-reload-button"
          "urlbar-container"
          "downloads-button"
          "ublock0_raymondhill_net-browser-action"
          "_testpilot-containers-browser-action"
          "reset-pbm-toolbar-button"
          "unified-extensions-button"
        ];
        toolbar-menubar = [ "menubar-items" ];
        TabsToolbar = [ "tabbrowser-tabs" ];
        vertical-tabs = [ ];
        PersonalToolbar = [ "personal-bookmarks" ];
      };
      seen = [
        "save-to-pocket-button"
        "developer-button"
        "ublock0_raymondhill_net-browser-action"
        "_testpilot-containers-browser-action"
        "screenshot-button"
      ];
      dirtyAreaCache = [
        "nav-bar"
        "PersonalToolbar"
        "toolbar-menubar"
        "TabsToolbar"
        "widget-overflow-fixed-list"
      ];
      currentVersion = 23;
      newElementCount = 10;
    };

    # === Ultima Theme ===
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;
    "ultima.spacing.compact.tabs" = true;
    "ultima.tabs.pinned.transparent.background" = true;
    "ultima.tabs.tabgroups.background.1" = true;
    "ultima.navbar.float" = false;
    "ultima.tabs.horizontal.under.navbar" = true;
    "ultima.spacing.compact.menupanel" = true;
    "ultima.contextmenu.reduce.options" = true;
    "ultima.spacing.compact.contextmenu" = true;

    # === Miscellaneous ===
    "middlemouse.paste" = false;
  };
in
{
  # FF-ULTIMA owns the chrome; disabling stylix's firefox target prevents it
  # from rewriting profile theming. This module ships browser mimeApps
  # defaultApplications, so it owns the mimeApps toggle.
  stylix.targets.firefox.enable = false;
  xdg.mimeApps.enable = true;

  programs.browserpass.enable = true;
  programs.firefox = {
    enable = true;
    configPath = "${config.xdg.configHome}/mozilla/firefox";
    profiles.nelieru = {
      id = 0;
      isDefault = true;
      search = sharedSearch;
      extensions.packages = sharedExtensions;
      bookmarks = { };
      settings = sharedSettings;
    };
    profiles.work = {
      id = 1;
      search = sharedSearch;
      extensions.packages = sharedExtensions;
      bookmarks = { };
      settings = sharedSettings;
    };
  };

  # Migrate the legacy ~/.mozilla/firefox profile tree to the XDG location used
  # by programs.firefox.configPath above. Runs before home-manager writes the
  # new firefox config, so the freshly-generated profiles.ini lands on top of
  # the migrated tree. Idempotent: leaves a symlink at the legacy path so any
  # process still hard-coding ~/.mozilla/firefox keeps working, and re-runs
  # short-circuit on that symlink.
  home.activation.migrateFirefoxToXdg = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
    legacy="$HOME/.mozilla/firefox"
    target="${config.xdg.configHome}/mozilla/firefox"
    backup="$HOME/.mozilla/firefox.bak"
    hmDefault="nelieru"

    if [ -L "$legacy" ] || [ ! -d "$legacy" ]; then
      :  # already migrated or nothing to migrate
    else
      run mkdir -p "$target/$hmDefault"

      if [ -f "$legacy/profiles.ini" ]; then
        defaultPath=$(${pkgs.gawk}/bin/awk '
          /^\[/                      { in_profile = ($0 ~ /^\[Profile/); path=""; def=0; next }
          in_profile && /^Path=/     { path = substr($0, 6) }
          in_profile && /^Default=1/ { def = 1 }
          in_profile && path != "" && def { print path; exit }
        ' "$legacy/profiles.ini")

        if [ -n "$defaultPath" ] && [ -d "$legacy/$defaultPath" ]; then
          run cp -an "$legacy/$defaultPath/." "$target/$hmDefault/"
        fi
      fi

      if [ -e "$backup" ]; then
        run rm -rf "$backup"
      fi
      run mv "$legacy" "$backup"
      run ln -sfn "$target" "$legacy"
    fi
  '';

  xdg.configFile."mozilla/firefox/nelieru/chrome" = {
    source = "${ultimaTheme}";
    recursive = true;
  };
  xdg.configFile."mozilla/firefox/work/chrome" = {
    source = "${ultimaTheme}";
    recursive = true;
  };

  xdg.desktopEntries.firefox-work = {
    name = "Firefox (Work)";
    genericName = "Web Browser";
    exec = "${lib.getExe pkgs.firefox} -P work --name FirefoxWork %u";
    icon = "firefox";
    terminal = false;
    categories = [
      "Network"
      "WebBrowser"
    ];
    startupNotify = true;
    settings = {
      StartupWMClass = "FirefoxWork";
    };
    mimeType = [
      "text/html"
      "text/xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    actions = {
      new-window = {
        name = "New Window";
        exec = "${lib.getExe pkgs.firefox} -P work --name FirefoxWork --new-window %u";
      };
      new-private-window = {
        name = "New Private Window";
        exec = "${lib.getExe pkgs.firefox} -P work --name FirefoxWork --private-window %u";
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "text/xml" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
  };
}
