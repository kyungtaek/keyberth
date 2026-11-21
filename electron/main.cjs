const { app, BrowserWindow, dialog, ipcMain, Menu, nativeImage, screen, Tray } = require('electron');
const { spawn, spawnSync } = require('node:child_process');
const { createInterface } = require('node:readline');
const path = require('node:path');
const { fileURLToPath } = require('node:url');

const { installPermissionGuide } = require('./permissions/guide.cjs');

const page = path.join(__dirname, 'index.html');
const helper = app.isPackaged ? path.join(process.resourcesPath, 'KeyberthBridge')
  : path.join(__dirname, '../.build/debug/MicroCompanion');
let bridge, tray, editor, quitting = false, serial = 0;
const pending = new Map();
let hud, hudTimer, hudMessage, hudReady = false;
function showHud(message) {
  hudMessage = message;
  if (!hud) {
    hud = new BrowserWindow({width:300, height:84, frame:false, transparent:true, show:false,
      focusable:false, resizable:false, fullscreenable:false, skipTaskbar:true, hasShadow:false,
      webPreferences:{preload:path.join(__dirname,'hud-preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false}});
    hud.setIgnoreMouseEvents(true);
    hud.setAlwaysOnTop(true, 'floating');
    hud.setVisibleOnAllWorkspaces(true, {visibleOnFullScreen:true,skipTransformProcessType:true});
    hud.webContents.once('did-finish-load', () => {
      let applied = false;
      try {
        const glass = require('electron-liquid-glass');
        applied = glass.isGlassSupported() && glass.addView(hud.getNativeWindowHandle(), {cornerRadius:20, opaque:false}) >= 0;
      } catch (error) { console.warn('HUD material:', error.message); }
      if (!applied) hud.setVibrancy('hud');
      hudReady = true;
      showHud(hudMessage);
    });
    hud.loadFile(path.join(__dirname,'hud.html'));
    return;
  }
  if (!hudReady) return;
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  const guide = Boolean(message.keys?.length);
  const width = Math.min(area.width, guide ? 352 : 420);
  const height = guide ? 112 : Math.min(area.height, Math.max(80, 36 + 34 * Math.ceil(Array.from(message.subtitle || '').length / 17)));
  hud.setSize(width,height);
  hud.setPosition(Math.round(area.x+(area.width-width)/2), Math.round(area.y+Math.max(0,area.height-height-32)));
  hud.webContents.send('hud', message);
  hud.showInactive();
  clearTimeout(hudTimer);
  hudTimer = setTimeout(() => hud.hide(), message.keys?.length ? 2300 : 1500);
}
function startBridge() {
  const child = spawn(helper, process.argv.includes('--agent-diagnostics') ? ['--agent-diagnostics'] : [],
    { stdio: ['pipe', 'pipe', 'inherit'] });
  bridge = child;
  const ended = () => {
    if (bridge !== child) return;
    bridge = null;
    for (const request of pending.values()) request.reject(new Error('USB 서비스 연결이 끊겼습니다.'));
    pending.clear();
  };
  child.on('error', ended);
  child.on('exit', ended);
  child.stdin.on('error', ended);
  createInterface({ input: child.stdout }).on('line', line => {
    let reply;
    try { reply = JSON.parse(line); } catch { return; }
    if (reply.event === 'hud') { showHud(reply); return; }
    const request = pending.get(reply.id);
    if (!request) return;
    pending.delete(reply.id);
    if (reply.error) request.reject(new Error(reply.error));
    else request.resolve(reply.value);
  });
}

function request(method, data = {}) {
  if (!bridge) startBridge();
  const id = ++serial;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error('기기 응답 시간 초과')); }, 24000);
    pending.set(id, {
      resolve(value) { clearTimeout(timer); resolve(value); },
      reject(error) { clearTimeout(timer); reject(error); }
    });
    bridge.stdin.write(JSON.stringify({ ...data, method, id }) + '\n');
  });
}

function makeWindow() {
  const {width,height}=screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workAreaSize;
  const win = new BrowserWindow({
    width:Math.min(width,1400), height:Math.min(height,900),
    minWidth:Math.min(width,840), minHeight:Math.min(height,600),
    show:false, title:'Keyberth', backgroundColor:'#141619', titleBarStyle:'hiddenInset',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), sandbox: true, contextIsolation: true, nodeIntegration: false }
  });
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', event => event.preventDefault());
  win.webContents.on('did-finish-load', () => win.webContents.send('firmware-progress',firmwareProgress));
  win.loadFile(page);
  win.on('close', event => { if (!quitting) { event.preventDefault(); if (!firmwareProgress) win.hide(); } });
  return win;
}
function openEditor(view = 'mapping') {
  if (!editor) editor = makeWindow();
  const win = editor;
  const show = () => { if (!firmwareProgress) win.webContents.send('view', view); win.show(); win.focus(); };
  if (win.webContents.isLoading()) win.webContents.once('did-finish-load', show);
  else show();
}
let firmwareProgress = '';
function showFirmwareProgress(message) {
  firmwareProgress = message;
  if (message) openEditor('device');
  editor?.webContents.send('firmware-progress',message);
  editor?.setProgressBar(message ? 2 : -1);
  for (const item of Menu.getApplicationMenu()?.items || []) item.enabled = !message;
}
const firmwareControls=require('./firmware.cjs').firmwareControls(app,dialog,()=>request('connect'),showFirmwareProgress);
ipcMain.handle('command', async (event, method, data) => {
  if (fileURLToPath(event.senderFrame.url) !== page) throw new Error('Unknown window');
  if (firmwareProgress && !['state','catalog'].includes(method)) throw new Error('펌웨어 작업 중입니다.');
  if (method==='manageFirmware' && editor && event.sender===editor.webContents)
    return firmwareControls.manage(data?.action);
  if (['addProfile','removeProfile','addFavorite','removeFavorite'].includes(method)) {
    if (!editor || event.sender!==editor.webContents) throw Error('편집 창에서 키맵을 관리하세요.');
    if (method==='removeFavorite') return request(method,{profile:data.profile});
    if (method==='removeProfile') {
      const choice=await dialog.showMessageBox(editor,{message:(data.name || data.profile)+' 키맵을 삭제할까요?',detail:'저장된 키 배정도 삭제됩니다.',buttons:['취소','삭제'],cancelId:0,defaultId:0});
      return choice.response===1 ? request(method,{profile:data.profile}) : null;
    }
    if (data?.profile) return request(method,{profile:data.profile});
    const pick=await dialog.showOpenDialog(editor,{title:method==='addFavorite'?'즐겨찾는 앱 선택':'키맵을 추가할 앱 선택',defaultPath:'/Applications',properties:['openFile'],filters:[{name:'macOS 앱',extensions:['app']}]});
    return pick.canceled ? null : request(method,{target:pick.filePaths[0]});
  }
  if ((method==='installClaudeHooks'||method==='removeClaudeHooks') && editor && event.sender===editor.webContents) {
    await require('./claude-hooks.cjs').configure(helper,method==='installClaudeHooks');
    return true;
  }
  if (['importMaps','exportMaps'].includes(method) && editor && event.sender === editor.webContents) {
    return require('./keymap-files.cjs').transfer(method, editor, dialog, request);
  }
  if (method === 'chooseNote') {
    if (event.sender !== editor?.webContents) throw new Error('편집 창에서 문서를 선택하세요.');
    const pick = await dialog.showOpenDialog(editor, {
      title:'Obsidian 보관함 문서 선택', properties:['openFile'], filters:[{name:'Markdown 문서',extensions:['md']}]
    });
    if (pick.canceled || !pick.filePaths.length) return null;
    const fs = require('node:fs/promises');
    const note = pick.filePaths[0];
    let folder = path.dirname(note);
    while (folder !== path.dirname(folder)) {
      if ((await fs.stat(path.join(folder,'.obsidian')).catch(() => null))?.isDirectory()) return 'obsidian-note:' + note;
      folder = path.dirname(folder);
    }
    throw new Error('Obsidian 보관함 안의 Markdown 문서를 선택하세요.');
  }
  if (method === 'editor' && ['mapping','device','sessions'].includes(data?.view)) return openEditor(data.view);
  if (!['state','catalog','appMenus','runningApps','applyPreset','save','select','connect','readPrefs','savePrefs','readLighting','saveLighting','activateProfile','toggleAuto','configureClaude'].includes(method)) throw new Error('Unknown command');
  const result = await request(method, data);
  return result;
});
if (process.argv.includes('--check-device')) {
  app.exit(spawnSync(helper, ['--check-device'], { stdio: 'inherit' }).status ?? 1);
} else if (!app.requestSingleInstanceLock()) app.quit();
else {
  app.on('second-instance', () => openEditor());
  app.whenReady().then(() => {
    startBridge();
    const icon = nativeImage.createFromPath(path.join(__dirname, 'tray.png')).resize({width:18,height:18});
    icon.setTemplateImage(true);
    tray = new Tray(icon); tray.setToolTip('Keyberth'); tray.on('click', () => openEditor());
    const permissionGuide = installPermissionGuide(request, () => editor);
    const checkUpdates = require('./updates.cjs').configureUpdates(() => { quitting = true; }, () => !firmwareProgress);
    const items = [{ label:'키 매핑', click:()=>openEditor() }, { label:'기기 설정…', accelerator:'Cmd+,', click:()=>openEditor('device') },
      firmwareControls.menu,
      {label:'권한 안내…', click:()=>{ openEditor(); permissionGuide.showOnDemand(); }},
      {label:'업데이트 확인…',click:checkUpdates}, {type:'separator'}, {label:'Keyberth 종료', role:'quit'}];
    tray.on('right-click', async () => {
      if (firmwareProgress) { openEditor(); return; }
      let controls;
      try {
        const state = await request('state');
        const change = (method, data) => request(method, data).catch(error => dialog.showErrorBox('키맵 변경 실패', error.message));
        controls = [{label:'포커스된 앱으로 자동 전환', type:'checkbox', checked:state.automatic, click:()=>change('toggleAuto')},
          ...[{id:"unconfigured",name:"글로벌"},...state.profiles].map(profile => ({label:profile.name, type:'radio', checked:profile.id === state.profile,
            click:()=>change('activateProfile', {profile:profile.id})}))];
      } catch {
        controls = [{label:'키맵 연결 대기 중', enabled:false}];
      }
      if (firmwareProgress) return;
      tray.popUpContextMenu(Menu.buildFromTemplate([...controls, {type:'separator'}, ...items]));
    });
    Menu.setApplicationMenu(Menu.buildFromTemplate([{label:'Keyberth', submenu:items},{role:'editMenu'},{role:'windowMenu'}]));
    openEditor(process.argv.includes('--show-slots') ? 'sessions' : 'mapping');
    permissionGuide.checkAtStartup();
  });
  app.on('activate', () => {
    if (!editor || !editor.isVisible()) openEditor();
  });
  app.on('before-quit', event => { if (firmwareProgress) { event.preventDefault(); return; } quitting = true; bridge?.stdin.end(); });
  app.on('window-all-closed', () => {});
}
