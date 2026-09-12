import { useRef, type KeyboardEvent } from "react";

// Use rendered positions so navigation follows both responsive grids and
// variable-width kaomoji rows, including movement between catalog groups.
export function useEmojiNavigation(onEscape: () => void) {
  const panelRef = useRef<HTMLElement>(null);

  function onKeyDown(event: KeyboardEvent<HTMLElement>) {
    if (event.defaultPrevented || event.nativeEvent.isComposing || event.keyCode === 229
      || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    if (event.key === "Escape") {
      event.preventDefault();
      onEscape();
      return;
    }
    const target = event.target as HTMLElement;
    const fromSearch = target.matches(".emoji-panel-search input");
    const current = target.closest<HTMLButtonElement>("[data-emoji-navigation-item]");
    if ((!current && !fromSearch) || (fromSearch && event.key !== "ArrowDown")) return;
    const keys = ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home", "End", "PageUp", "PageDown"];
    if (!keys.includes(event.key)) return;
    const items = Array.from(panelRef.current?.querySelectorAll<HTMLButtonElement>("[data-emoji-navigation-item]:not(:disabled)") ?? []);
    if (!items.length) return;
    event.preventDefault();
    const index = current ? items.indexOf(current) : -1;
    let next = Math.max(0, index);
    if (index < 0 || event.key === "Home") next = 0;
    else if (event.key === "End") next = items.length - 1;
    else if (event.key === "ArrowLeft") next = Math.max(0, index - 1);
    else if (event.key === "ArrowRight") next = Math.min(items.length - 1, index + 1);
    else {
      const origin = items[index].getBoundingClientRect();
      const originX = origin.left + origin.width / 2;
      const direction = event.key === "ArrowUp" || event.key === "PageUp" ? -1 : 1;
      const pageStep = event.key === "PageUp" || event.key === "PageDown";
      const viewport = items[index].closest(".emoji-panel-content");
      const destinationY = origin.top + (pageStep ? direction * (viewport?.clientHeight || origin.height) : 0);
      let bestVertical = Infinity;
      let bestHorizontal = Infinity;
      for (let candidate = 0; candidate < items.length; candidate++) {
        const rect = items[candidate].getBoundingClientRect();
        if ((rect.top - origin.top) * direction <= 1) continue;
        const vertical = Math.abs(rect.top - destinationY);
        const horizontal = Math.abs(rect.left + rect.width / 2 - originX);
        if (vertical < bestVertical - 1 || (Math.abs(vertical - bestVertical) <= 1 && horizontal < bestHorizontal)) {
          next = candidate;
          bestVertical = vertical;
          bestHorizontal = horizontal;
        }
      }
    }
    items[next].focus({ preventScroll: true });
    items[next].scrollIntoView({ block: "nearest", inline: "nearest" });
  }

  return { ref: panelRef, onKeyDown };
}
