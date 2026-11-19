const { ipcRenderer } = require('electron');
ipcRenderer.on('hud', (_, message) => {
  document.getElementById('title').textContent = message.title;
  document.getElementById('detail').textContent = message.subtitle;
});
