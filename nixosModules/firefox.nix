{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.programs) firefox sway;
  inherit (lib) mkDefault mkIf;
  inherit (pkgs) bash ibm-plex;
  inherit (pkgs.thoughtfull) writeFileScript;
  login = writeFileScript {
    name = "firefox-login";
    replacements = {
      bash = "${bash}/bin/bash";
      firefox = "${firefox.finalPackage}/bin/firefox";
      swaymsg = "${sway.package}/bin/swaymsg";
    };
    src = ./firefox/login.bash;
  };
in
{
  fonts.packages = mkIf firefox.enable [ ibm-plex ];
  programs.firefox = {
    policies = {
      CaptivePortal = false;
      DisableFirefoxStudies = true;
      DisablePocket = true;
      DisableTelemetry = true;
      Extensions.Install = [
        "https://addons.mozilla.org/firefox/downloads/file/3426972/archiveror-0.15.1.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/3551985/happy_bonobo_disable_webrtc-1.0.23.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/4627302/multi_account_containers-8.3.6.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/4625020/proton_pass-1.33.0.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/3535009/redirector-3.5.3.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/4598854/ublock_origin-1.67.0.xpi"
        "https://addons.mozilla.org/firefox/downloads/file/3670210/unofficial_hypothesis-1.470.0.2.xpi"
      ];
      FirefoxHome = {
        Pocket = false;
        Snippets = false;
      };
      UserMessaging = {
        ExtensionRecommendations = false;
        SkipOnboarding = true;
      };
    };
    preferences = {
      "app.shield.optoutstudies.enabled" = false;
      "browser.aboutConfig.showWarning" = false;
      "browser.aboutwelcome.enabled" = false;
      "browser.contentblocking.category" = "strict";
      "browser.crashReports.unsubmittedCheck.autoSubmit2" = false;
      "browser.discovery.enabled" = false;
      "browser.download.dir" = "/tmp";
      "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons" = false;
      "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;
      "browser.newtabpage.activity-stream.feeds.section.highlights" = false;
      "browser.newtabpage.activity-stream.feeds.topsites" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeBookmarks" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeDownloads" = false;
      "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
      "browser.newtabpage.activity-stream.section.highlights.includeVisited" = false;
      "browser.newtabpage.activity-stream.showSearch" = false;
      "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
      "browser.newtabpage.enabled" = false;
      "browser.safebrowsing.downloads.enabled" = false;
      "browser.safebrowsing.downloads.remote.block_potentially_unwanted" = false;
      "browser.safebrowsing.downloads.remote.block_uncommon" = false;
      "browser.safebrowsing.malware.enabled" = false;
      "browser.safebrowsing.phishing.enabled" = false;
      "browser.search.suggest.enabled" = false;
      "browser.search.suggest.enabled.private" = false;
      "browser.startup.homepage" = "about:blank";
      "browser.startup.page" = 3;
      "browser.tabs.warnOnClose" = false;
      "browser.urlbar.showSearchSuggestionsFirst" = false;
      "browser.urlbar.suggest.searches" = false;
      "browser.warnOnQuitShortcut" = false;
      "datareporting.healthreport.uploadEnabled" = false;
      "datareporting.policy.dataSubmissionPolicyAcceptedVersion" = 2;
      "datareporting.policy.dataSubmissionPolicyNotifiedTime" = "1656951310242";
      "dom.event.clipboardevents.enable" = false;
      "dom.security.https_only_mode" = true;
      "dom.security.https_only_mode_ever_enabled" = true;
      "font.minimum-size.x-western" = 16;
      "font.name.monospace.x-western" = "IBM Plex Mono";
      "font.name.sans-serif.x-western" = "IBM Plex Sans";
      "font.name.serif.x-western" = "IBM Plex Serif";
      "font.size.monospace.x-western" = 16;
      "font.size.variable.x-western" = 16;
      "layout.css.prefers-color-scheme.content-override" = 2;
      "media.autoplay.default" = 5;
      "network.captive-portal-service.enabled" = true;
      "network.cookie.cookieBehavior" = 5;
      "network.cookie.lifetimePolicy" = 2;
      "network.http.referer.disallowCrossSiteRelaxingDefault.top_navigation" = true;
      "permissions.default.camera" = 0;
      "permissions.default.desktop-notification" = 2;
      "permissions.default.geo" = 2;
      "permissions.default.microphone" = 0;
      "permissions.default.xr" = 2;
      "privacy.annotate_channels.strict_list.enabled" = true;
      "privacy.donottrackheader.enabled" = true;
      "privacy.history.custom" = true;
      "privacy.partition.network_state.ocsp_cache" = true;
      "privacy.query_stripping.enabled" = true;
      "privacy.sanitize.pending" = "[{\"id\":\"newtab-container\",\"itemsToClear\":[],\"options\":{}}]";
      "privacy.sanitize.sanitizeOnShutdown" = false;
      "privacy.trackingprotection.enabled" = true;
      "privacy.trackingprotection.socialtracking.enabled" = true;
      "signon.autofillForms" = false;
      "signon.generation.enabled" = false;
      "signon.management.page.breach-alerts.enabled" = false;
      "signon.rememberSignons" = false;
      "toolkit.telemetry.reportingpolicy.firstRun" = false;
      "trailhead.firstrun.branches" = "nofirstrun-empty";
      "ui.key.menuAccessKey" = -1;
      "urlclassifier.malwareTable" = "goog-malware-proto,moztest-harmful-simple,moztest-malware-simple";
    };
  };
  thoughtfull.impermanence.user.directories = mkIf firefox.enable [ ".config/mozilla/firefox" ];
  systemd.user.services.firefox-login = {
    description = "Launch firefox on workspace 3 at login";
    after = [
      "sway-session.target"
      "waybar.service"
    ];
    # See gtk-defaults in sway.nix for why partOf (follow sway-session down)
    # rather than bindsTo (would also pull sway-session.target up on a lone
    # `systemctl --user start firefox-login.service`, which isn't wanted
    # here).
    partOf = [ "sway-session.target" ];
    enable = mkDefault (sway.enable && firefox.enable);
    wantedBy = [ "sway-session.target" ];
    # A rebuild-switch that touches this unit's closure (e.g. a firefox/sway
    # package bump) shouldn't relaunch firefox mid-session.
    restartIfChanged = mkDefault false;
    serviceConfig = {
      Type = "oneshot";
      # See foot-login in foot.nix for why oneshot + RemainAfterExit, and
      # for KillMode=process, here.
      RemainAfterExit = true;
      KillMode = "process";
      ExecStart = "${login}";
    };
  };
}
