const { ipcRenderer } = require('electron');

window.addEventListener('DOMContentLoaded', () => {
  const status = document.querySelector('[role="status"]');
  ipcRenderer.on('permission-message', (_, message) => { status.textContent = message; });
  for (const button of document.querySelectorAll('button[data-action]')) {
    button.onclick = async () => {
      button.disabled = true;
      try {
        const action = button.dataset.action;
        const ready = await ipcRenderer.invoke('permission-guide', action);
        if (action === 'check' && !ready) status.textContent = '권한 대기 중 · 설정에서 이미 켰다면 Keyberth를 종료한 뒤 다시 여세요.';
        if (action === 'open') status.textContent = '권한을 켜면 이 안내 창이 자동으로 닫힙니다.';
      } catch {
        status.textContent = '시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 확인하세요.';
      } finally { button.disabled = false; }
    };
  }
});
