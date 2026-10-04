// Slide viewer: a lightbox, and a switch between the thumbnail grid and a
// continuous vertical read.
//
// No dependencies and no build step, matching the rest of the project. The
// markup works without any of this — every page is a link to its own image —
// so everything here is an enhancement layered on top.
(function () {
  "use strict";

  var slides = document.getElementById("slides");
  var lightbox = document.getElementById("lightbox");
  if (!slides || !lightbox || typeof lightbox.showModal !== "function") return;

  var links = Array.prototype.slice.call(slides.querySelectorAll(".slide-link"));
  var image = document.getElementById("lb-image");
  var counter = document.getElementById("lb-counter");
  var current = 0;

  // --- lightbox ----------------------------------------------------------

  function show(index) {
    if (index < 0 || index >= links.length) return;
    current = index;

    var link = links[index];
    image.src = link.href;
    image.alt = link.querySelector("img").alt;
    counter.textContent = index + 1 + " / " + links.length;

    document.getElementById("lb-prev").disabled = index === 0;
    document.getElementById("lb-next").disabled = index === links.length - 1;

    preload(index + 1);
    preload(index - 1);
  }

  // Fetching the neighbours now means the next arrow press paints instantly
  // instead of flashing an empty frame while a 200KB page image arrives.
  function preload(index) {
    if (index < 0 || index >= links.length) return;
    new Image().src = links[index].href;
  }

  function open(index) {
    show(index);
    lightbox.showModal();
  }

  links.forEach(function (link, index) {
    link.addEventListener("click", function (event) {
      // Leave modified clicks alone: they mean "open this elsewhere".
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.button !== 0) return;
      event.preventDefault();
      open(index);
    });
  });

  document.getElementById("lb-prev").addEventListener("click", function () {
    show(current - 1);
  });
  document.getElementById("lb-next").addEventListener("click", function () {
    show(current + 1);
  });
  document.getElementById("lb-close").addEventListener("click", function () {
    lightbox.close();
  });

  // Clicking the backdrop closes. The dialog element itself fills the
  // viewport, so a click landing on it rather than on its contents is a
  // click outside the image.
  lightbox.addEventListener("click", function (event) {
    if (event.target === lightbox) lightbox.close();
  });

  lightbox.addEventListener("keydown", function (event) {
    if (event.key === "ArrowRight" || event.key === "ArrowDown") {
      event.preventDefault();
      show(current + 1);
    } else if (event.key === "ArrowLeft" || event.key === "ArrowUp") {
      event.preventDefault();
      show(current - 1);
    }
  });

  // Returning to the grid on a different page than you left from is
  // disorienting; scroll the page you were last looking at into view.
  lightbox.addEventListener("close", function () {
    var link = links[current];
    if (link) link.scrollIntoView({ block: "center" });
  });

  // --- view mode ---------------------------------------------------------

  var STORAGE_KEY = "gento:view";
  var toggle = document.getElementById("view-toggle");

  function applyView(view) {
    slides.dataset.view = view;
    Array.prototype.forEach.call(toggle.querySelectorAll("button"), function (button) {
      button.setAttribute("aria-pressed", String(button.dataset.view === view));
    });
    try {
      localStorage.setItem(STORAGE_KEY, view);
    } catch (error) {
      // Private browsing can refuse storage. The mode still applies.
    }
  }

  toggle.addEventListener("click", function (event) {
    var button = event.target.closest("button[data-view]");
    if (button) applyView(button.dataset.view);
  });

  var stored;
  try {
    stored = localStorage.getItem(STORAGE_KEY);
  } catch (error) {
    stored = null;
  }
  applyView(stored === "scroll" ? "scroll" : "grid");

  toggle.hidden = false;
})();
