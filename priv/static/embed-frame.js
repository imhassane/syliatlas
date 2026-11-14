// Syli Atlas: the script of a framed view (/embed/…, SyliAtlasWeb.EmbedController).
// Loaded in the <head>, before the first paint:
//   1. theme "auto" follows the reader's system setting;
//   2. the frame tells the host page its height, so the <iframe> fits its
//      content (read by /embed.js on the host page). Only a number is sent.
(function () {
  var root = document.documentElement;
  try {
    if (root.dataset.embedTheme === "auto" && matchMedia("(prefers-color-scheme: dark)").matches) {
      root.dataset.theme = "dark";
    }
  } catch (e) {}

  if (window.parent === window) return;

  var last = 0;
  var send = function () {
    var height = Math.ceil(document.documentElement.getBoundingClientRect().height);
    if (height === last) return;
    last = height;
    // "*": the host's origin is not known here, and a height is no secret.
    // The host page (embed.js) checks the sender's origin and frame.
    window.parent.postMessage({type: "syli-atlas:embed-height", height: height}, "*");
  };

  var start = function () {
    send();
    if (window.ResizeObserver) new ResizeObserver(send).observe(document.body);
    else window.addEventListener("resize", send);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(send);
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
