const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('keyberth', {
  command: (method, data) => ipcRenderer.invoke('command', method, data),
  onView: listener => ipcRenderer.on('view', (_, view) => listener(view))
});
