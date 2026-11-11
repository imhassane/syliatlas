(function () {
  try {
    var t = localStorage.getItem("theme");
    if (!t) t = matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    document.documentElement.dataset.theme = t;
  } catch (e) {}
  document.documentElement.classList.add("js");
  // Entrance animations play once per page and session. A page prepared in
  // advance (speculation rules below) counts as seen only once shown.
  var markSeen = function () {
    try {
      var seen = JSON.parse(sessionStorage.getItem("seen") || "[]");
      if (seen.indexOf(location.pathname) >= 0) document.documentElement.classList.add("revisit");
      else sessionStorage.setItem("seen", JSON.stringify(seen.concat(location.pathname).slice(-50)));
    } catch (e) {}
  };
  if (document.prerendering) document.addEventListener("prerenderingchange", markSeen, {once: true});
  else markSeen();
  if (!navigator.onLine) document.documentElement.classList.add("is-offline");
})();
