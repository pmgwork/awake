// Run the shipped observer against a small AE API boundary. These tests cover
// callback ownership and render transitions, not the AE host's own API behavior.
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = readFileSync(new URL('../awake/Resources/after-effects-monitor.jsx', `file://${__filename}`), 'utf8')
  .replace('__AWAKE_CONFIG__', JSON.stringify({controlPath: '/control', signalPath: '/signal', token: 'session'}));
function host() {
  const files = new Map([['/control', 'session']]);
  let writesAllowed = true;
  function File(path) { this.path = path; }
  Object.defineProperty(File.prototype, 'exists', {get() { return files.has(this.path); }});
  File.prototype.open = function() { return writesAllowed; };
  File.prototype.write = function(text) { files.set(this.path, text); };
  File.prototype.close = function() {};
  File.prototype.remove = function() { files.delete(this.path); };
  const items = [{status: 'QUEUED', onStatusChanged: 'other.finished'}];
  const queue = {rendering: false, get numItems() { return items.length; }, item(i) { return items[i-1]; }};
  let calls = 0, cancelled = false;
  const global = {other: {finished() { calls++; }}};
  const context = vm.createContext({File, $: {global}, RQItemStatus: {RENDERING: 'RENDERING'},
    app: {project: {renderQueue: queue}, scheduleTask() { return 1; }, cancelTask() { cancelled = true; }}});
  function run() { vm.runInContext(source, context); }
  function change(status) { items[0].status = status; global[items[0].onStatusChanged](); }
  return {files, items, queue, global, run, change,
    report: () => JSON.parse(files.get('/signal')).active,
    calls: () => calls, cancelled: () => cancelled,
    forbidWrites: () => { writesAllowed = false; }};
}
{
  const h = host(); h.run();
  assert.equal(h.report(), false); // queued/editing/preview alone is idle
  h.queue.rendering = true;
  h.change('RENDERING'); assert.equal(h.report(), true);
  // No timer or heartbeat is needed during a long frame.
  h.change('WILL_CONTINUE'); assert.equal(h.report(), false);
  h.change('RENDERING'); assert.equal(h.report(), true);
  h.change('USER_STOPPED'); assert.equal(h.report(), false);
  h.change('ERR_STOPPED'); assert.equal(h.report(), false);
  h.change('DONE'); assert.equal(h.report(), false);
  assert.equal(h.calls(), 6); // original callback is preserved exactly once
  h.queue.rendering = false;
  h.files.delete('/control'); h.global.__awakeAE.tick();
  assert.equal(h.items[0].onStatusChanged, 'other.finished');
  assert.equal(h.cancelled(), true);
  assert.equal(h.files.has('/signal'), false);
}
{
  const h = host(); h.run(); h.queue.rendering = true; h.change('RENDERING');
  assert.throws(() => h.run(), /current render/); // never replace a live callback
  h.files.delete('/control'); h.change('DONE'); assert.equal(h.report(), false);
  assert.equal(h.global.__awakeAE.dispose(), false); // restore only when AE permits
  h.queue.rendering = false; h.global.__awakeAE.tick(); assert.equal(h.cancelled(), true);
}
{
  const h = host(); h.run();
  const second = {status: 'QUEUED', onStatusChanged: null};
  h.items.push(second); h.global.__awakeAE.tick();
  assert.equal(typeof h.global[second.onStatusChanged], 'function');
  const wrapper = second.onStatusChanged;
  h.items.pop(); h.global.__awakeAE.tick(); assert.equal(h.global[wrapper], undefined);
  h.forbidWrites(); h.queue.rendering = true;
  assert.doesNotThrow(() => h.change('RENDERING'));
  assert.equal(h.calls(), 1); // notification failure never breaks another script
}
{
  const h = host(); h.forbidWrites(); assert.throws(() => h.run(), /allow scripts/);
  assert.equal(h.items[0].onStatusChanged, 'other.finished');
}
console.log('After Effects observer: 4 scenarios passed');
