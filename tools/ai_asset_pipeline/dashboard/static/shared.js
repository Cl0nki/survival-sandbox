// The top bar every dashboard page shares. To add a tool, add one line here and one
// route in dashboard/server.py. The current page is marked from its address.
(function () {
  const TOOLS = [
    ["Workshop", "/"],
    ["Codex", "/codex"],
    ["Sounds", "/sounds"],
  ];

  function here() {
    const path = location.pathname.replace(/\/index\.html$/, "/");
    return path.length > 1 ? path.replace(/\/$/, "") : "/";
  }

  function build() {
    if (document.querySelector(".toolnav")) return;
    const bar = document.createElement("div");
    bar.className = "toolnav";
    bar.setAttribute("role", "navigation");
    bar.setAttribute("aria-label", "Survival Sandbox tools");
    const mark = document.createElement("span");
    mark.className = "brand-mark";
    mark.textContent = "Survival Sandbox";
    bar.append(mark);
    TOOLS.forEach(([label, href]) => {
      const link = document.createElement("a");
      link.href = href;
      link.textContent = label;
      if (href === here()) link.setAttribute("aria-current", "page");
      bar.append(link);
    });
    document.body.prepend(bar);
  }

  if (document.body) build();
  else document.addEventListener("DOMContentLoaded", build);
})();
