// Real browser hit-testing complements the isolated runtime listener harness.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const test = require('node:test');

const browser = [process.env.CMUX_CONTEXT_TEST_CHROME,
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome'
].find(candidate => candidate && fs.existsSync(candidate));
const runtime = fs.readFileSync(process.env.CMUX_CONTEXT_RUNTIME_PATH ||
    'Packages/macOS/CmuxBrowser/Sources/CmuxBrowser/Resources/BrowserContextSelectionRuntime.js', 'utf8');

test('embedded hit-testing stays disabled after animation and in the modal top layer', { skip: !browser }, () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cmux-context-hit-test-'));
    try {
        const html = `<!doctype html><html><head><meta charset="utf-8"><style>
            body { margin:0; width:1000px; height:800px; }
            iframe, object, embed { border:0; width:160px; height:80px; }
            #moving { position:absolute; left:20px; top:20px; }
            #modal { width:300px; height:180px; }
        </style></head><body>
            <iframe id="moving" style="pointer-events:auto !important" srcdoc="<button>Embedded app</button>"></iframe>
            <dialog id="modal"><iframe id="inside" srcdoc="<button>Modal app</button>"></iframe></dialog>
            <pre id="result">pending</pre>
            <script>window.webkit = { messageHandlers: { cmuxContextSelection: { postMessage() {} } } };</script>
            <script>${runtime.replaceAll('</script', '<\\/script')}</script>
            <script>
            (async () => {
                const failures = [], passed = [];
                const check = (condition, name) => (condition ? passed : failures).push(name);
                const hit = element => {
                    const bounds = element.getBoundingClientRect();
                    return document.elementFromPoint(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
                };
                const moving = document.getElementById('moving');
                check(hit(moving) === moving, 'fixture starts with an interactive frame');
                const animation = moving.animate([{ transform:'translateX(0px)' }, { transform:'translateX(400px)' }], { duration:1000, fill:'both' });
                animation.pause(); animation.currentTime = 0;
                window.__cmuxContextPicker.start('geometry');
                check(hit(moving) !== moving, 'frame initially excludes pointer hit-testing');
                // Web Animations geometry changes do not fire scroll/resize or DOM mutations.
                animation.currentTime = 800;
                check(moving.getBoundingClientRect().x > 300, 'animation moved the frame without a DOM mutation');
                check(hit(moving) !== moving, 'animated frame still excludes pointer hit-testing');
                window.__cmuxContextPicker.stop();
                check(moving.style.getPropertyValue('pointer-events') === 'auto' && moving.style.getPropertyPriority('pointer-events') === 'important', 'inline value and priority restored');
                check(hit(moving) === moving, 'animated frame becomes interactive after stop');
                animation.cancel();

                const modal = document.getElementById('modal');
                const inside = document.getElementById('inside');
                modal.showModal();
                check(hit(inside) === inside, 'fixture modal frame is above ordinary document overlays');
                window.__cmuxContextPicker.start('top-layer');
                check(hit(inside) !== inside, 'modal top-layer frame excludes pointer hit-testing');
                for (const tag of ['iframe', 'object', 'embed']) {
                    const dynamic = document.createElement(tag);
                    modal.appendChild(dynamic);
                    await Promise.resolve();
                    check(getComputedStyle(dynamic).pointerEvents === 'none', 'dynamic ' + tag + ' is blocked');
                    dynamic.style.setProperty('pointer-events', 'auto', 'important');
                    await Promise.resolve();
                    check(getComputedStyle(dynamic).pointerEvents === 'none', 'page rewrite cannot re-enable ' + tag);
                }
                window.__cmuxContextPicker.stop();
                check(inside.style.getPropertyValue('pointer-events') === '' && inside.style.getPropertyPriority('pointer-events') === '', 'absent inline declaration restored');
                check(hit(inside) === inside, 'modal frame becomes interactive after stop');
                document.getElementById('result').textContent = JSON.stringify({ passed, failures });
            })().catch(error => { document.getElementById('result').textContent = JSON.stringify({ failures:[String(error)] }); });
            </script></body></html>`;
        const fixture = path.join(directory, 'fixture.html');
        fs.writeFileSync(fixture, html);
        const output = execFileSync(browser, ['--headless', '--disable-gpu', '--disable-background-networking',
            '--disable-extensions', '--no-first-run', '--no-default-browser-check', '--disable-sync',
            '--disable-component-update', '--disable-default-apps', '--window-size=1000,800',
            '--user-data-dir=' + path.join(directory, 'profile'), '--dump-dom', pathToFileURL(fixture).href
        ], { encoding: 'utf8', timeout: 30000, stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 2 * 1024 * 1024 });
        const result = output.match(/<pre id="result">([^<]*)<\/pre>/)?.[1];
        assert.ok(result && result !== 'pending', 'browser fixture completed');
        const report = JSON.parse(result);
        assert.deepEqual(report.failures, []);
        assert.ok(report.passed.length >= 15, 'all real browser checks executed');
    } finally {
        fs.rmSync(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
    }
});
