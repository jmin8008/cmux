// Behavior harness for the isolated picker. It drives its actual DOM listeners.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const test = require('node:test');
const source = fs.readFileSync('Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/Resources/BrowserContextSelectionRuntime.js', 'utf8');
function fixture(contentType = 'text/html') {
    const handlers = new Map(), messages = [], frames = [], created = [];
    let mutation;
    const bounds = { x: 20, y: 30, width: 70, height: 25 };
    const registered = new Set();
    const body = { tagName: 'BODY', children: [], closest: () => null };
    const element = { id: 'save', tagName: 'BUTTON', innerText: 'Save', parentElement: body, closest: () => null, getBoundingClientRect: () => bounds };
    const selected = { text: '', rangeCount: 0, toString() { return this.text; }, removeAllRanges() { this.text = ''; this.rangeCount = 0; }, getRangeAt() { return { commonAncestorContainer: element, getBoundingClientRect: () => bounds }; } };
    element.nodeType = 1;
    const document = { contentType, querySelectorAll: () => frames, body, documentElement: { appendChild() {} }, createElement: () => { const node = { style: {}, setAttribute() {}, remove() {} }; created.push(node); return node; } };
    const window = { getSelection: () => selected, addEventListener(name, fn) { handlers.set(name, fn); registered.add(fn); }, removeEventListener(name, fn) { handlers.delete(name); registered.delete(fn); }, webkit: { messageHandlers: { cmuxContextSelection: { postMessage(message) { messages.push(message); } } } } };
    const sandbox = { MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} disconnect() { mutation = null; } }, window, document, location: { href: 'http://localhost:3000' }, crypto: { randomUUID: () => 'capture-1' }, CSS: { escape: s => s }, Node: { ELEMENT_NODE: 1 }, innerWidth: 1000, innerHeight: 800, scrollX: 0, scrollY: 200 };
    vm.runInNewContext(source, sandbox);
    window.__cmuxContextPicker.start('revision-1');
    function fire(name, extra = {}) {
        const event = { button: 0, isTrusted: true, target: element, clientX: 22, clientY: 35, prevented: false, stopped: false, preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }, ...extra };
        handlers.get(name)?.(event);
        return event;
    }
    return { window, document, element, selected, fire, messages, sandbox, bounds, registered, handlers, frames, created, mutate: () => mutation?.([{ type: 'childList', target: body }]) };
}
test('click sends one element at mouse-up and suppresses activation', () => {
    const f = fixture();
    f.fire('mousedown');
    assert.equal(f.messages.length, 0);
    f.fire('mouseup');
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].capture.kind, 'element');
    assert.equal(f.messages[0].capture.text, 'Save');
    assert.equal(f.fire('click').prevented, true);
    assert.equal(f.messages.length, 1);
});
test('text drag sends only text, empty drag sends nothing', () => {
    const f = fixture();
    f.fire('mousedown');
    f.fire('mousemove', { clientX: 100 });
    f.selected.text = 'selected words'; f.selected.rangeCount = 1;
    f.fire('mouseup', { clientX: 100 });
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].capture.kind, 'text');
    assert.equal(f.messages[0].capture.viewport.scroll_y, 200);
    f.fire('mousedown'); f.fire('mousemove', { clientX: 100 }); f.fire('mouseup');
    assert.equal(f.messages.length, 1);
});
test('input contents and oversized selection are never delivered', () => {
    const f = fixture();
    f.fire('mousedown', { target: { closest: () => true } }); f.fire('mouseup');
    assert.equal(f.messages.length, 0);
    f.element.innerText = 'x'.repeat(32769);
    f.fire('mousedown'); f.fire('mouseup');
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].type, 'too_large');
});
test('image clicks contain alt text only and Escape restores page listeners', () => {
    const f = fixture();
    f.element.tagName = 'IMG'; f.element.getAttribute = () => 'Company logo';
    f.fire('mousedown'); f.fire('mouseup');
    assert.equal(f.messages[0].capture.text, 'Company logo');
    assert.deepEqual(Object.keys(f.messages[0].capture).sort(), ['bounds', 'id', 'kind', 'revision', 'selector', 'tag', 'text', 'url', 'viewport']);
    f.fire('keydown', { key: 'Escape' });
    assert.equal(f.handlers.size, 0);
    assert.equal(f.messages.at(-1).type, 'exit');
    assert.equal(f.fire('click').prevented, false);
});

test('non-HTML viewers are rejected and disabling mid-drag cancels the gesture', () => {
    const pdf = fixture('application/pdf');
    assert.equal(pdf.handlers.size, 0);
    const f = fixture();
    f.fire('mousedown');
    f.window.__cmuxContextPicker.stop();
    f.fire('mouseup');
    assert.equal(f.messages.length, 0);
    assert.equal(f.handlers.size, 0);
});

function embeddedElement(value = '', priority = '') {
    const properties = new Map(value ? [['pointer-events', { value, priority }]] : []);
    return {
        closest() { return this; },
        getBoundingClientRect() { return { left: 500, right: 800, top: 500, bottom: 700, width: 300, height: 200 }; },
        style: {
            getPropertyValue: name => properties.get(name)?.value || '',
            getPropertyPriority: name => properties.get(name)?.priority || '',
            setProperty(name, value, priority = '') { properties.set(name, { value, priority }); },
            removeProperty(name) { properties.delete(name); }
        }
    };
}

test('new embedded documents block hit-testing and restore original inline value and priority', () => {
    const f = fixture();
    const frames = [embeddedElement(), embeddedElement('auto'), embeddedElement('auto', 'important')];
    f.frames.push(...frames);
    f.mutate();
    for (const frame of frames) {
        assert.equal(frame.style.getPropertyValue('pointer-events'), 'none');
        assert.equal(frame.style.getPropertyPriority('pointer-events'), 'important');
        assert.equal(f.fire('mousedown', { target: frame }).prevented, true);
        f.fire('mouseup', { target: frame });
    }
    assert.equal(f.messages.length, 0);
    f.window.__cmuxContextPicker.stop();
    assert.deepEqual(frames.map(frame => frame.style.getPropertyValue('pointer-events')), ['', 'auto', 'auto']);
    assert.deepEqual(frames.map(frame => frame.style.getPropertyPriority('pointer-events')), ['', '', 'important']);
});

test('removed embeds are restored and page inline rewrites are blocked until stop', () => {
    const f = fixture();
    const frame = embeddedElement('auto', 'important');
    f.frames.push(frame); f.mutate();
    frame.style.setProperty('pointer-events', 'auto'); f.mutate();
    assert.equal(frame.style.getPropertyValue('pointer-events'), 'none');
    f.frames.pop(); f.mutate();
    assert.equal(frame.style.getPropertyValue('pointer-events'), 'auto');
    assert.equal(frame.style.getPropertyPriority('pointer-events'), 'important');
});

test('clicks through a disabled embedded document never capture the element behind it', () => {
    const f = fixture();
    const frame = embeddedElement();
    f.frames.push(frame); f.mutate();
    const down = f.fire('mousedown', { clientX: 550, clientY: 550 });
    assert.equal(down.prevented, true);
    f.fire('mouseup', { clientX: 550, clientY: 550 });
    assert.equal(f.messages.length, 0);
});

test('capture reports geometry and scroll at mouse-up when the page scrolls during the gesture', () => {
    const f = fixture();
    f.fire('mousedown');
    f.bounds.y = -270.25; f.sandbox.scrollY = 500.5;
    f.fire('mouseup');
    const capture = f.messages[0].capture;
    assert.equal(capture.bounds.y, -270.25);
    assert.equal(capture.viewport.scroll_y, 500.5);
    assert.equal(capture.bounds.y + capture.viewport.scroll_y, 230.25);
});

test('page zoom changes are reported in CSS pixels on the next capture without stale values', () => {
    const f = fixture();
    f.fire('mousedown'); f.fire('mouseup');
    // Browser zoom of 200 percent halves the CSS viewport and keeps rects in CSS pixels.
    Object.assign(f.bounds, { x: 10.5, y: 15, width: 35, height: 12.5 });
    Object.assign(f.sandbox, { innerWidth: 500, innerHeight: 400, scrollX: 0.5 });
    f.fire('mousedown'); f.fire('mouseup');
    assert.equal(f.messages.length, 2);
    assert.deepEqual(JSON.parse(JSON.stringify(f.messages[1].capture.viewport)), { width: 500, height: 400, scroll_x: 0.5, scroll_y: 200 });
    assert.deepEqual(JSON.parse(JSON.stringify(f.messages[1].capture.bounds)), { x: 10.5, y: 15, width: 35, height: 12.5 });
    assert.deepEqual(JSON.parse(JSON.stringify(f.messages[0].capture.bounds)), { x: 20, y: 30, width: 70, height: 25 });
});

test('restarting with a new revision replaces listeners and never reports the old revision', () => {
    const f = fixture();
    const before = f.registered.size;
    assert.ok(before > 0);
    f.window.__cmuxContextPicker.start('revision-2');
    assert.equal(f.registered.size, before);
    f.fire('mousedown'); f.fire('mouseup');
    assert.equal(f.messages.length, 1);
    assert.equal(f.messages[0].capture.revision, 'revision-2');
    f.window.__cmuxContextPicker.stop();
    assert.equal(f.registered.size, 0);
    assert.equal(f.created.every(node => typeof node.remove === 'function'), true);
});

test('a stopped picker is inert for every gesture event and can be armed again', () => {
    const f = fixture();
    f.window.__cmuxContextPicker.stop();
    for (const name of ['mousedown', 'mousemove', 'mouseup', 'click', 'keydown']) {
        const event = f.fire(name, { key: 'Escape' });
        assert.equal(event.prevented, false);
        assert.equal(event.stopped, false);
    }
    assert.equal(f.messages.length, 0);
    assert.equal(f.window.__cmuxContextPicker.start('revision-3'), true);
    f.fire('mousedown'); f.fire('mouseup');
    assert.equal(f.messages.at(-1).capture.revision, 'revision-3');
});
