(function () {
  var EASE = "cubic-bezier(.22, 1, .36, 1)";
  var read = function () {
    try {
      var saved = JSON.parse(sessionStorage.getItem("arrival"));
      if (saved && saved.to === location.href) { sessionStorage.removeItem("arrival"); return saved; }
    } catch (x) {}
    return null;
  };
  var early = read();
  if (early) {
    var expect = document.createElement("link");
    expect.rel = "expect";
    expect.href = early.kind === "tab" ? "#tab-panel" : "#vt-ready";
    expect.setAttribute("blocking", "render");
    document.head.appendChild(expect);
  }
  // The band keeps its place from page to page: its loop position follows
  // the clock (assets/css/ticker.css, mod()).
  document.documentElement.style.setProperty("--now", Date.now() / 1000 + "s");

  var arrive = function () {
    // A page prepared in advance read nothing while it was being prepared.
    var saved = early || read();
    early = null;
    if (!saved) return;
    var still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    var band = document.getElementById("site-ticker");
    var stickyTop = band ? band.offsetHeight : 0;
    var move = function (el, from, ms) {
      if (!still && el && el.animate) el.animate([{transform: from}, {transform: "none"}], {duration: ms || 320, easing: EASE});
    };
    // Same place as on the old page, also when the link carried an anchor
    // (the anchor would scroll once more at the end of parsing).
    var keep = function (y) {
      if (location.hash) history.replaceState(history.state, "", location.pathname + location.search);
      scrollTo({top: y, behavior: "instant"});
      if (document.readyState === "loading")
        document.addEventListener("DOMContentLoaded", function () { scrollTo({top: y, behavior: "instant"}); }, {once: true});
    };

    if (saved.kind === "tab") {
      var bar = document.querySelector(".tab-bar"), panel = document.getElementById("tab-panel");
      if (!bar || !panel) return;
      keep(panel.getBoundingClientRect().top + scrollY - bar.offsetHeight - Math.max(saved.top, stickyTop));
      // Near the top of a page whose hero is shorter, the bar cannot stay:
      // it glides to its new place instead of jumping.
      var gap = Math.max(saved.top, stickyTop) - bar.getBoundingClientRect().top;
      if (Math.abs(gap) > 1) move(bar, "translateY(" + gap + "px)");
      var ind = bar.querySelector(".tab-indicator");
      if (ind && saved.ind) {
        var r = ind.getBoundingClientRect();
        move(ind, "translateX(" + (saved.ind.left - r.left) + "px) scaleX(" + saved.ind.width / r.width + ")");
      }
      move(panel, "translateX(" + 32 * saved.dir + "px)");
    } else if (saved.kind === "reorder") {
      var box = document.querySelector("[data-keep-place]");
      if (!box) return;
      keep(scrollY + box.getBoundingClientRect().top - Math.max(saved.top, stickyTop));
      var top0 = box.getBoundingClientRect().top;
      Array.prototype.forEach.call(document.querySelectorAll("[data-reorder] > [id]"), function (row) {
        var was = saved.rows[row.id];
        var now = row.getBoundingClientRect().top - top0;
        if (was == null) move(row, "translateY(12px)");
        else if (Math.abs(was - now) > 1) move(row, "translateY(" + (was - now) + "px)", 380);
      });
    }
  };
  if ("onpagereveal" in window) addEventListener("pagereveal", arrive);
  else document.addEventListener("DOMContentLoaded", arrive);
})();
