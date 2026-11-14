// Syli Atlas: sizes the frames of Syli Atlas on a host page (a newspaper, a blog).
//
//   <iframe src="https://syliatlas.com/embed/…" data-syli-embed …></iframe>
//   <script async src="https://syliatlas.com/embed.js"></script>
//
// Each frame sends its height (/embed-frame.js); this script sets it on the
// matching <iframe>, so there is no scroll bar and no gap. Only messages from
// Syli Atlas' own origin, and only from one of its frames, are read. Without
// this script the frame keeps the height written in the code.
(function () {
  if (window.__syliAtlasEmbed) return;
  window.__syliAtlasEmbed = true;

  var script = document.currentScript;
  var origin = script ? new URL(script.src).origin : "https://syliatlas.com";

  window.addEventListener("message", function (event) {
    if (event.origin !== origin) return;
    var data = event.data;
    if (!data || data.type !== "syli-atlas:embed-height") return;
    var height = Number(data.height);
    if (!(height > 0 && height < 5000)) return;

    var frames = document.querySelectorAll("iframe");
    for (var i = 0; i < frames.length; i++) {
      if (frames[i].contentWindow === event.source) {
        frames[i].style.height = height + "px";
        frames[i].setAttribute("height", String(height));
        return;
      }
    }
  });
})();
