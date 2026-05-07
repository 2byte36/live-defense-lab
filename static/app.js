(function () {
  function pingHealth() {
    fetch("/health", { cache: "no-store" }).catch(function () {});
  }

  function fetchJson(path) {
    return fetch(path, {
      cache: "no-store",
      headers: { "Accept": "application/json" }
    }).then(function (response) {
      if (!response.ok) {
        throw new Error("request failed");
      }
      return response.json();
    });
  }

  pingHealth();
  window.setInterval(pingHealth, 20000);

  if (document.body.dataset.authenticated !== "true") {
    return;
  }

  function pollInternalApis() {
    fetchJson("/api/tickets").catch(function () {});
    fetchJson("/api/notifications").catch(function () {});
    fetchJson("/api/stats").catch(function () {});
  }

  pollInternalApis();
  window.setInterval(pollInternalApis, 30000);
})();
