const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('keyberth', {
  command: (method, data) => ipcRenderer.invoke('command', method, data),
  onFirmwareProgress: listener => ipcRenderer.on('firmware-progress', (_, message) => listener(message)),
  onView: listener => ipcRenderer.on('view', (_, view) => listener(view))
});
