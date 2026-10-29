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
    const body = { tagName: 'BODY', children: [], closest: () => null };
    const element = { id: 'save', tagName: 'BUTTON', innerText: 'Save', parentElement: body, closest: () => null, getBoundingClientRect: () => bounds };
    const selected = { text: '', rangeCount: 0, toString() { return this.text; }, removeAllRanges() { this.text = ''; this.rangeCount = 0; }, getRangeAt() { return { commonAncestorContainer: element, getBoundingClientRect: () => bounds }; } };
    element.nodeType = 1;
    const document = { contentType, querySelectorAll: () => frames, body, documentElement: { appendChild() {} }, createElement: () => { const node = { style: {}, setAttribute() {}, remove() {} }; created.push(node); return node; } };
    const window = { getSelection: () => selected, addEventListener(name, fn) { handlers.set(name, fn); }, removeEventListener(name) { handlers.delete(name); }, webkit: { messageHandlers: { cmuxContextSelection: { postMessage(message) { messages.push(message); } } } } };
    vm.runInNewContext(source, { MutationObserver: class { constructor(fn) { mutation = fn; } observe() {} disconnect() { mutation = null; } }, window, document, location: { href: 'http://localhost:3000' }, crypto: { randomUUID: () => 'capture-1' }, CSS: { escape: s => s }, Node: { ELEMENT_NODE: 1 }, innerWidth: 1000, innerHeight: 800, scrollX: 0, scrollY: 200 });
    window.__cmuxContextPicker.start('revision-1');
    function fire(name, extra = {}) {
        const event = { button: 0, isTrusted: true, target: element, clientX: 22, clientY: 35, prevented: false, stopped: false, preventDefault() { this.prevented = true; }, stopImmediatePropagation() { this.stopped = true; }, ...extra };
        handlers.get(name)?.(event);
        return event;
    }
    return { window, document, element, selected, fire, messages, handlers, frames, created, mutate: () => mutation?.([{ target: body }]) };
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

test('new embedded frames are shielded and never captured', () => {
    const f = fixture();
    f.frames.push({ getBoundingClientRect: () => ({ x: 0, y: 0, width: 300, height: 200 }) });
    f.mutate();
    const shield = f.created.at(-1);
    assert.equal(shield.style.width, '300px');
    assert.equal(f.fire('mousedown', { target: shield }).prevented, true);
    f.fire('mouseup', { target: shield });
    assert.equal(f.messages.length, 0);
});
