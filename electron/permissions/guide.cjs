const { BrowserWindow, dialog, ipcMain, shell } = require('electron');
const path = require('node:path');
const { pathToFileURL } = require('node:url');

const page = path.join(__dirname, 'guide.html');
const settingsURL = 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility';

function installPermissionGuide(request, getParent) {
  let guide;
  let timer;
  let checking = false;
  async function check() {
    const status = await request('controlPermission');
    return status.accessibility === true && status.postEvents === true;
  }
  function show(initialMessage = '') {
    if (guide) { guide.show(); guide.focus(); return; }
    const win = new BrowserWindow({
      parent: getParent(), modal: false, title: 'Keyberth 권한 안내', titleBarStyle: 'hiddenInset',
      width: 600, height: 478, minWidth: 540, minHeight: 478, show: false, fullscreenable: false,
      backgroundColor: '#191b20',
      webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false }
    });
    guide = win;
    win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
    win.webContents.on('will-navigate', event => event.preventDefault());
    win.webContents.once('did-finish-load', () => {
      if (initialMessage) win.webContents.send('permission-message', initialMessage);
      win.show();
      win.focus();
    });
    async function recheck() {
      if (checking || win.isDestroyed()) return;
      checking = true;
      try {
        if (await check() && !win.isDestroyed()) win.close();
      } catch {
        if (!win.isDestroyed()) win.webContents.send('permission-message', '권한 상태를 읽을 수 없습니다. 잠시 후 다시 확인하세요.');
      } finally { checking = false; }
    }
    timer = setInterval(recheck, 1800);
    win.on('focus', recheck);
    win.once('closed', () => { clearInterval(timer); guide = undefined; });
    win.loadFile(page);
  }
  ipcMain.handle('permission-guide', async (event, action) => {
    if (!guide || event.sender !== guide.webContents ||
        event.senderFrame !== event.sender.mainFrame || event.senderFrame.url !== pathToFileURL(page).href) {
      throw new Error('권한 안내 창을 다시 열어 주세요.');
    }
    if (action === 'later') { guide.close(); return; }
    if (action === 'open') {
      try { await request('requestControlPermission'); }
      finally { await shell.openExternal(settingsURL); }
      return;
    }
    if (action === 'check') {
      const ready = await check();
      if (ready) guide?.close();
      return ready;
    }
    throw new Error('알 수 없는 요청입니다.');
  });
  return {
    async checkAtStartup() {
      try {
        if (!(await check())) show();
      } catch {
        show('권한 상태를 읽을 수 없습니다. 잠시 후 다시 확인하세요.');
      }
    },
    async showOnDemand() {
      try {
        if (await check()) {
          await dialog.showMessageBox(getParent(), { type:'info', message:'손쉬운 사용 권한이 켜져 있습니다.', buttons:['확인'] });
          return;
        }
      } catch {
        show('권한 상태를 읽을 수 없습니다. 잠시 후 다시 확인하세요.');
        return;
      }
      show();
    }
  };
}
module.exports = { installPermissionGuide };
