(function () {
  "use strict";

  var script = document.currentScript;
  var activeVersion = script
    ? script.getAttribute("data-theme-version") || ""
    : "";
  var loadingVersion = "";

  function currentStylesheet() {
    return document.querySelector(
      'link[rel~="stylesheet"][href^="assets/css/theme.css"]'
    );
  }

  function applyTheme(version) {
    if (!version || version === activeVersion || loadingVersion) {
      return;
    }

    var current = currentStylesheet();
    if (!current || !current.parentNode) return;

    loadingVersion = version;
    var replacement = current.cloneNode();
    replacement.href = "assets/css/theme.css?v="
      + encodeURIComponent(version);
    replacement.addEventListener("load", function () {
      activeVersion = version;
      loadingVersion = "";
      current.remove();
    }, { once: true });
    replacement.addEventListener("error", function () {
      loadingVersion = "";
      replacement.remove();
    }, { once: true });
    current.parentNode.insertBefore(replacement, current.nextSibling);
  }

  function checkTheme() {
    if (document.hidden) return;

    fetch("/theme-assets/syncthing-omarchy/theme-version.txt", {
      cache: "no-store",
      credentials: "same-origin"
    }).then(function (response) {
      if (!response.ok) throw new Error("theme version unavailable");
      return response.text();
    }).then(function (value) {
      var version = value.trim();
      if (/^[A-Za-z0-9._-]+$/.test(version)) applyTheme(version);
    }).catch(function () {});
  }

  document.addEventListener("visibilitychange", checkTheme);
  window.setInterval(checkTheme, 1000);
  checkTheme();
})();
