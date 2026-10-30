import { useEffect } from "react";

/**
 * Global MD3 ripple / state-layer feedback.
 * - Every <button> ripples automatically (opt out with `data-noripple`).
 * - Any element can opt in with `data-ripple`.
 * - `data-ripple-in=".selector"` draws the ripple inside a child
 *   (e.g. the pill indicator of a navigation item).
 * Works inside CSS-scaled containers (the phone mock) by compensating the scale.
 */
export function useRipple() {
  useEffect(() => {
    const onDown = (e: PointerEvent) => {
      if (e.button !== 0) return;
      const origin = e.target instanceof Element ? e.target : null;
      const btn = origin?.closest<HTMLElement>("button, [data-ripple]");
      if (!btn || btn.hasAttribute("data-noripple") || (btn as HTMLButtonElement).disabled) return;

      const sel = btn.getAttribute("data-ripple-in");
      const surface = (sel && btn.querySelector<HTMLElement>(sel)) || btn;
      const w = surface.offsetWidth;
      const h = surface.offsetHeight;
      if (!w || !h) return;

      const rect = surface.getBoundingClientRect();
      const sx = rect.width / w || 1;
      const sy = rect.height / h || 1;
      const x = (e.clientX - rect.left) / sx;
      const y = (e.clientY - rect.top) / sy;
      if (getComputedStyle(surface).position === "static") surface.style.position = "relative";

      const r = Math.hypot(Math.max(x, w - x), Math.max(y, h - y));
      const host = document.createElement("span");
      host.className = "ripple-host";
      const dot = document.createElement("span");
      dot.className = "ripple-dot";
      dot.style.width = `${r * 2}px`;
      dot.style.height = `${r * 2}px`;
      dot.style.left = `${x - r}px`;
      dot.style.top = `${y - r}px`;
      host.appendChild(dot);
      surface.appendChild(host);

      const t0 = performance.now();
      const release = () => {
        window.removeEventListener("pointerup", release);
        window.removeEventListener("pointercancel", release);
        const wait = Math.max(0, 260 - (performance.now() - t0));
        window.setTimeout(() => {
          dot.classList.add("out");
          window.setTimeout(() => host.remove(), 420);
        }, wait);
      };
      window.addEventListener("pointerup", release);
      window.addEventListener("pointercancel", release);
    };

    document.addEventListener("pointerdown", onDown);
    return () => document.removeEventListener("pointerdown", onDown);
  }, []);
}
