// The documentation page: the menu darkens once the page scrolls, and the list of sections follows the reader.
(() => {
  "use strict";
  const nav = document.querySelector("[data-nav]");
  const settle = () => nav?.classList.toggle("is-scrolled", window.scrollY > 24);
  window.addEventListener("scroll", settle, { passive: true });
  settle();

  const links = [...document.querySelectorAll("[data-toc] a")];
  const byId = new Map(links.map((link) => [link.getAttribute("href").slice(1), link]));
  if (!("IntersectionObserver" in window)) return;
  const spy = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      links.forEach((link) => link.classList.remove("is-current"));
      byId.get(entry.target.id)?.classList.add("is-current");
    }
  }, { rootMargin: "-20% 0px -70% 0px" });
  document.querySelectorAll(".prose section[id]").forEach((section) => spy.observe(section));
})();
