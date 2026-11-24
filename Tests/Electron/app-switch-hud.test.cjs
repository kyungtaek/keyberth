const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { test } = require('node:test');
const vm = require('node:vm');

const src = readFileSync(new URL('../../electron/main.cjs', 'file:' + __filename), 'utf8');
const from = src.indexOf('let hud, hudTimer');
const to = src.indexOf('function startBridge');
assert(from >= 0 && to > from);

function simulateHud() {
  const calls = [];
  let loaded;
  let timer;
  const hud = vm.runInNewContext(src.slice(from, to) + '\n({showHud,dismissAppSwitchHud})', {
    BrowserWindow: class {
      webContents = { once(_, callback) { loaded = callback; }, send(_, message) { calls.push(message.subtitle); } };
      setIgnoreMouseEvents() {}
      setAlwaysOnTop() {}
      setVisibleOnAllWorkspaces() {}
      setVibrancy() {}
      setSize() {}
      setPosition() {}
      loadFile() {}
      showInactive() { calls.push('show'); }
      hide() { calls.push('hide'); }
    },
    path: { join() {} },
    __dirname: '',
    require() { return { isGlassSupported: () => false }; },
    screen: { getDisplayNearestPoint: () => ({ workArea:{ x:0, y:0, width:800, height:600 } }), getCursorScreenPoint() {} },
    setTimeout(fn) { timer = fn; return 1; },
    clearTimeout() { timer = null; },
  });
  return { ...hud, calls, didFinishLoad: () => loaded(), expire: () => timer?.() };
}

test('turning off auto-switch HUD cancels a pending window load', () => {
  const hud = simulateHud();
  hud.showHud({ subtitle:'switch', fromAppSwitch:true });
  hud.dismissAppSwitchHud();
  hud.didFinishLoad();
  assert.deepEqual(hud.calls, ['hide']);
});

test('turning off auto-switch HUD hides only the most recent auto-switch event', () => {
  const hud = simulateHud();
  hud.showHud({ subtitle:'switch 1', fromAppSwitch:true });
  hud.didFinishLoad();
  hud.showHud({ subtitle:'switch 2', fromAppSwitch:true });
  hud.dismissAppSwitchHud();
  hud.expire();
  hud.showHud({ subtitle:'error notice' });
  hud.dismissAppSwitchHud();
  hud.expire();
  assert.deepEqual(hud.calls, ['switch 1','show','switch 2','show','hide','error notice','show','hide']);
});
