const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const path = require('node:path');
const run = promisify(execFile);

function firmwareControls(app, dialog, reconnect) {
  const dir = app.isPackaged ? path.join(process.resourcesPath, 'firmware') : path.join(__dirname,'../dist/firmware');
  let busy = false;
  async function manage(action) {
    if (!['install','update','reset','rollback'].includes(action)) throw new Error('지원하지 않는 펌웨어 작업입니다.');
    if (busy) return 'busy';
    busy = true;
    try {
      const actions = {
        install: ['키버스 펌웨어 0.4.1 설치','Mac 본체에 USB로 연결하세요. 정품 백업을 검증하고 별도 파티션에 설치합니다.'],
        update: ['키버스 펌웨어 0.4.1 업데이트','USB 연결을 유지하세요. 기존 키버스 설정과 페어링을 유지합니다.'],
        reset: ['키버스 기기 공장 초기화','키버스 펌웨어 0.4.1의 조명, 절전, 부저 설정과 Bluetooth 페어링 3개를 지웁니다. Mac의 키맵은 유지됩니다.'],
        rollback: ['Universal Agent 0.2.18로 복귀','보존된 정품 파티션으로 다시 부팅합니다.']
      };
      const [title,detail] = actions[action];
      const choice = await dialog.showMessageBox({type:action==='reset'?'warning':'question',message:title,
        detail,buttons:['취소',title],defaultId:0,cancelId:0});
      if (choice.response !== 1) return 'cancelled';
      const {stdout}=await run(path.join(dir,'keyberth-firmware'),[action,path.join(dir,'keyberth-0.4.1.bin')]);
      if (stdout.trim()==='already-current') {
        await dialog.showMessageBox({message:'키버스 펌웨어 0.4.1이 이미 설치되어 있습니다.',buttons:['확인']});
        return 'current';
      }
      await reconnect();
      await dialog.showMessageBox({message:title+' 완료',buttons:['확인']});
      return 'done';
    } catch (error) {
      const lines=(error.stderr || error.message).trim().split(/\r?\n/);
      const reason=lines.filter(line=>line.trim() && !/^\[PYI-/.test(line)).at(-1);
      dialog.showErrorBox('펌웨어 작업을 완료하지 못했습니다.',reason || error.message);
      return 'failed';
    } finally { busy=false; }
  }
  return {manage, menu:{label:'기기 펌웨어',submenu:[
    {label:'키버스-펌웨어 0.4.1 설치…',click:()=>manage('install')},
    {label:'키버스 펌웨어 업데이트…',click:()=>manage('update')},
    {label:'기기 공장 초기화…',click:()=>manage('reset')},
    {label:'정품 Universal Agent로 롤백…',click:()=>manage('rollback')}
  ]}};
}
module.exports = {firmwareControls};
