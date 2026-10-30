(() => {
    "use strict";
    if (window.__cmuxContextPicker) return;
    let revision = null;
    let gesture = null;
    let style = null;
    let outline = null;
    const blockedEmbeds = new Map();
    let frameObserver = null;
    const listeners = [];
    const maximumCharacters = 32768;
    const post = message => window.webkit.messageHandlers.cmuxContextSelection.postMessage(message);
    const block = event => {
        event.preventDefault();
        event.stopImmediatePropagation();
    };
    const excluded = element => !element || element.closest("input, textarea, select, [contenteditable]:not([contenteditable='false']), script, style, iframe, object, embed");
    const overEmbeddedDocument = event => {
        for (const element of blockedEmbeds.keys()) {
            const bounds = element.getBoundingClientRect();
            if (bounds.width > 0 && bounds.height > 0 && event.clientX >= bounds.left && event.clientX <= bounds.right && event.clientY >= bounds.top && event.clientY <= bounds.bottom) return true;
        }
        return false;
    };
    const selector = element => {
        if (element.id) return "#" + CSS.escape(element.id);
        const testID = element.getAttribute("data-testid");
        if (testID) return element.tagName.toLowerCase() + "[data-testid=" + JSON.stringify(testID) + "]";
        const parts = [];
        for (let node = element; node && node !== document.body && parts.length < 5; node = node.parentElement) {
            const siblings = node.parentElement ? Array.from(node.parentElement.children).filter(sibling => sibling.tagName === node.tagName) : [];
            parts.unshift(node.tagName.toLowerCase() + (siblings.length > 1 ? ":nth-of-type(" + (siblings.indexOf(node) + 1) + ")" : ""));
        }
        return parts.join(" > ");
    };
    const rect = bounds => ({ x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height });
    const add = (name, fn) => {
        window.addEventListener(name, fn, true);
        listeners.push([name, fn]);
    };
    const stop = () => {
        for (const [name, fn] of listeners) window.removeEventListener(name, fn, true);
        listeners.length = 0;
        frameObserver?.disconnect();
        frameObserver = null;
        style?.remove();
        outline?.remove();
        for (const [element, original] of blockedEmbeds) {
            if (original.value) element.style.setProperty("pointer-events", original.value, original.priority);
            else element.style.removeProperty("pointer-events");
        }
        blockedEmbeds.clear();
        style = outline = null;
        gesture = null;
        revision = null;
    };
    const start = token => {
        stop();
        if (!document.body || !["text/html", "application/xhtml+xml"].includes(document.contentType)) return false;
        revision = token;
        style = document.createElement("style");
        style.textContent = "html body, html body * { cursor: crosshair !important; -webkit-user-select: text !important; user-select: text !important; }";
        document.documentElement.appendChild(style);
        outline = document.createElement("div");
        outline.setAttribute("aria-hidden", "true");
        outline.style.cssText = "position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #3578ee;background:rgba(53,120,238,.08);box-sizing:border-box;display:none";
        document.documentElement.appendChild(outline);
        // Child-frame events do not bubble here. Disable hit-testing on the
        // embedded element itself: geometry overlays cannot cover animation,
        // layout shifts, or content promoted into a modal dialog's top layer.
        const blockEmbeddedDocuments = () => {
            const embeds = new Set(document.querySelectorAll("iframe, object, embed"));
            for (const [element, original] of blockedEmbeds) {
                if (embeds.has(element)) continue;
                if (original.value) element.style.setProperty("pointer-events", original.value, original.priority);
                else element.style.removeProperty("pointer-events");
                blockedEmbeds.delete(element);
            }
            for (const element of embeds) {
                if (!blockedEmbeds.has(element)) {
                    blockedEmbeds.set(element, {
                        value: element.style.getPropertyValue("pointer-events"),
                        priority: element.style.getPropertyPriority("pointer-events")
                    });
                }
                // Avoid self-triggering observer cycles, but reassert the guard
                // if the page rewrites inline styles while selection is armed.
                if (element.style.getPropertyValue("pointer-events") !== "none" || element.style.getPropertyPriority("pointer-events") !== "important") {
                    element.style.setProperty("pointer-events", "none", "important");
                }
            }
        };
        blockEmbeddedDocuments();
        frameObserver = new MutationObserver(records => {
            if (records.some(record => record.type === "childList" || blockedEmbeds.has(record.target))) blockEmbeddedDocuments();
        });
        frameObserver.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style"] });
        add("pointerdown", event => {
            event.stopImmediatePropagation();
            if (excluded(event.target) || overEmbeddedDocument(event)) event.preventDefault();
        });
        add("mousedown", event => {
            event.stopImmediatePropagation();
            if (event.button !== 0 || !event.isTrusted || excluded(event.target) || overEmbeddedDocument(event)) {
                event.preventDefault();
                gesture = null;
                return;
            }
            window.getSelection()?.removeAllRanges();
            gesture = { x: event.clientX, y: event.clientY, target: event.target, moved: false };
        });
        add("mousemove", event => {
            event.stopImmediatePropagation();
            if (gesture && Math.hypot(event.clientX - gesture.x, event.clientY - gesture.y) > 4) gesture.moved = true;
            const element = event.target;
            if (excluded(element) || overEmbeddedDocument(event) || element === document.body || element === document.documentElement) {
                outline.style.display = "none";
                return;
            }
            const bounds = element.getBoundingClientRect();
            Object.assign(outline.style, { display: "block", left: bounds.x + "px", top: bounds.y + "px", width: bounds.width + "px", height: bounds.height + "px" });
        });
        add("mouseup", event => {
            event.stopImmediatePropagation();
            const current = gesture;
            gesture = null;
            if (!current || event.button !== 0 || !event.isTrusted) return;
            const selection = window.getSelection();
            const selectedText = selection?.toString() || "";
            const isText = current.moved && selectedText.trim().length > 0 && selection.rangeCount > 0;
            if (current.moved && !isText) return;
            let element = current.target;
            let bounds;
            let text;
            if (isText) {
                const range = selection.getRangeAt(0);
                const ancestor = range.commonAncestorContainer;
                element = ancestor.nodeType === Node.ELEMENT_NODE ? ancestor : ancestor.parentElement;
                if (excluded(element)) return;
                bounds = range.getBoundingClientRect();
                text = selectedText;
            } else {
                if (element === document.body || element === document.documentElement || excluded(element)) return;
                bounds = element.getBoundingClientRect();
                text = element.tagName === "IMG" ? element.getAttribute("alt") || "" : element.innerText || "";
            }
            const css = selector(element);
            if (text.length > maximumCharacters || css.length > maximumCharacters) {
                post({ type: "too_large", revision });
                return;
            }
            post({ type: "capture", capture: {
                id: crypto.randomUUID(), revision, url: location.href,
                kind: isText ? "text" : "element", text, selector: css, tag: element.tagName.toLowerCase(),
                bounds: rect(bounds),
                viewport: { width: innerWidth, height: innerHeight, scroll_x: scrollX, scroll_y: scrollY }
            } });
        });
        // Never allow a picked link/button/form control to perform its original action.
        for (const name of ["click", "auxclick", "dblclick", "contextmenu", "dragstart", "pointerup"]) add(name, block);
        add("keydown", event => {
            if (event.key === "Escape") {
                block(event);
                const oldRevision = revision;
                stop();
                post({ type: "exit", revision: oldRevision });
            }
        });
        return true;
    };
    window.__cmuxContextPicker = { start, stop };
})();
