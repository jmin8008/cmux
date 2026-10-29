(() => {
    "use strict";
    if (window.__cmuxContextPicker) return;
    let revision = null;
    let gesture = null;
    let style = null;
    let outline = null;
    let shields = [];
    let frameObserver = null;
    const listeners = [];
    const maximumCharacters = 32768;
    const post = message => window.webkit.messageHandlers.cmuxContextSelection.postMessage(message);
    const block = event => {
        event.preventDefault();
        event.stopImmediatePropagation();
    };
    const excluded = element => !element || shields.some(shield => shield.overlay === element) || element.closest("input, textarea, select, [contenteditable]:not([contenteditable='false']), script, style, iframe, object, embed");
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
        for (const shield of shields) shield.overlay.remove();
        shields = [];
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
        // Pointer events inside child frames do not bubble to this document.
        // Cover unsupported embedded documents so selection never activates them.
        const positionShields = () => {
            const frames = Array.from(document.querySelectorAll("iframe, object, embed"));
            for (const shield of shields) if (!frames.includes(shield.frame)) shield.overlay.remove();
            shields = shields.filter(shield => frames.includes(shield.frame));
            for (const frame of frames) {
                if (shields.some(shield => shield.frame === frame)) continue;
                const overlay = document.createElement("div");
                overlay.setAttribute("aria-hidden", "true");
                overlay.style.cssText = "position:fixed;z-index:2147483646;cursor:not-allowed;background:transparent";
                document.documentElement.appendChild(overlay);
                shields.push({ frame, overlay });
            }
            for (const { frame, overlay } of shields) {
                const bounds = frame.getBoundingClientRect();
                Object.assign(overlay.style, { left: bounds.x + "px", top: bounds.y + "px", width: bounds.width + "px", height: bounds.height + "px" });
            }
        };
        positionShields();
        frameObserver = new MutationObserver(records => {
            if (records.some(record => record.target !== style && record.target !== outline && !shields.some(shield => shield.overlay === record.target))) positionShields();
        });
        frameObserver.observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ["style", "class", "hidden"] });
        add("scroll", positionShields);
        add("resize", positionShields);
        add("pointerdown", event => {
            event.stopImmediatePropagation();
            if (excluded(event.target)) event.preventDefault();
        });
        add("mousedown", event => {
            event.stopImmediatePropagation();
            if (event.button !== 0 || !event.isTrusted || excluded(event.target)) {
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
            if (excluded(element) || element === document.body || element === document.documentElement) {
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
