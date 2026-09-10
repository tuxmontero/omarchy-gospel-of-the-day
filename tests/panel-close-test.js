const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

// Evaluate only the close helpers: never load QML or connect to the desktop.
const source = fs.readFileSync(process.argv[2] || path.join(__dirname, '../Panel.qml'), 'utf8');
const functions = ['close', 'setCenterHoverRevealSuppressed'].map(name => {
  const match = source.match(new RegExp('  function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}'));
  assert.ok(match, name);
  return match[0];
}).join('\n');

function context(bar, events) {
  const ctx = vm.createContext({root: {bar, controller: {hide() { events.push('hide'); }}}});
  vm.runInContext(functions, ctx);
  return ctx;
}

const events = [];
const bar = {setCenterHoverRevealSuppressed(value) { events.push(value); }};
Object.defineProperty(bar, 'centerHoverRevealSuppressed', {
  get() { return false; },
  set() { throw Error('Read-only property'); }
});
const ctx = context(bar, events);
ctx.setCenterHoverRevealSuppressed(true);
ctx.close();
assert.deepEqual(events, [true, 'hide', false]);

for (const missing of [null, {}]) {
  const calls = [];
  context(missing, calls).close();
  assert.deepEqual(calls, ['hide']);
}

const calls = [];
const failing = context({setCenterHoverRevealSuppressed() { throw Error('Host failure'); }}, calls);
assert.throws(() => failing.close(), /Host failure/);
assert.deepEqual(calls, ['hide'], 'Dismiss before any failing host operation');
console.log('Panel close regression checks passed');
