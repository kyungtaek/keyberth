const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const path = require('node:path');
const run = promisify(execFile);

function firmwareControls(app, dialog, reconnect, progress, suspend) {
  const dir = app.isPackaged ? path.join(process.resourcesPath, 'firmware') : path.join(__dirname,'../dist/firmware');
  const records=require('./firmware-history.cjs').history(app);
  const helper=path.join(dir,'keyberth-firmware');
  const image=path.join(dir,'keyberth-0.4.4.bin');
  let busy = false;
  async function manage(action) {
    if (!['install','update','reset','rollback','diagnose'].includes(action)) throw new Error('지원하지 않는 펌웨어 작업입니다.');
    const log=records.begin(action);
    function finish(result) { log.add('종료',{result}); return result; }
    if (busy) return finish('busy');
    busy = true;
    let paused=false, helperCompleted=false;
    try {
      const actions = {
        diagnose: ['펌웨어 진단',''],
        install: ['키버스 펌웨어 0.4.4 설치','Mac 본체에 USB로 연결하세요. 정품 백업을 검증하고 별도 파티션에 설치합니다.'],
        update: ['키버스 펌웨어 0.4.4 업데이트','USB 연결을 유지하세요. 기존 키버스 설정과 페어링을 유지합니다.'],
        reset: ['키버스 기기 공장 초기화','키버스 펌웨어 0.4.4의 조명, 절전, 부저 설정과 Bluetooth 페어링 3개를 지웁니다. Mac의 키맵은 유지됩니다.'],
        rollback: ['Universal Agent 0.2.18로 복귀','Universal Agent를 기본 부팅 펌웨어로 변경하고 재시작합니다.']
      };
      const [title,detail] = actions[action];
      if (action !== 'diagnose') {
      const choice = await dialog.showMessageBox({type:action==='reset'?'warning':'question',message:title,
        detail,buttons:['취소',title],defaultId:0,cancelId:0});
      if (choice.response !== 1) return finish('cancelled');
      }
      progress(({diagnose:'읽기 전용 진단 중',install:'펌웨어 설치 중',update:'펌웨어 업데이트 중',reset:'기기 초기화 중',rollback:'정품 펌웨어로 복귀 중'})[action]);
      if (action !== 'diagnose') { await suspend(); paused=true; }
      log.add('설치 관리자 시작',{helperVersion:'0.4.4'});
      const {stdout}=await run(helper,[action,image],{env:{...process.env,KEYBERTH_FIRMWARE_JOURNAL:log.file}});
      helperCompleted=true;
      log.add('설치 관리자 완료',{exit:0});
      if (action==='diagnose') {
        await dialog.showMessageBox({message:'펌웨어 진단 완료',detail:'연결된 펌웨어 '+stdout.trim(),buttons:['확인']});
        return finish('diagnosed');
      }
      log.add('앱 브리지 재연결');
      paused=false;
      await reconnect();
      if (stdout.trim()==='already-current') {
        await dialog.showMessageBox({message:'키버스 펌웨어 0.4.4가 이미 설치되어 있습니다.',buttons:['확인']});
        return finish('current');
      }

      await dialog.showMessageBox({message:title+' 완료',buttons:['확인']});
      return finish('done');
    } catch (error) {
      const lines=(error.stderr || error.message).trim().split(/\r?\n/);
      const reason=lines.filter(line=>line.trim() && !/^\[PYI-/.test(line)).at(-1);
      const safe=(reason || '작업 실패').replace(/(?:[0-9a-f]{2}:){5}[0-9a-f]{2}/ig,'[기기]').replace(/(?:\/[^\s]+)+/g,'[경로]').slice(0,240);
      const stages=log.read();
      const failedStage=stages.at(-1)?.stage;
      const lastSuccess=stages.at(-2)?.stage;
      log.add('오류',{failedStage,lastSuccess,error:safe,code:error.code ?? null,signal:error.signal ?? null});
      const result=finish(helperCompleted && action!=='diagnose' ? 'reconnect-failed' : 'failed');
      const choice=await dialog.showMessageBox({type:'error',message:result==='reconnect-failed'?'기기 작업 후 앱 재연결에 실패했습니다.':'펌웨어 작업을 완료하지 못했습니다.',
        detail:[safe,failedStage,'작업 ID '+log.id].join('\n'),buttons:['확인','진단 기록 복사']});
      if(choice.response===1) require('electron').clipboard.writeText(JSON.stringify(log.read(),null,2));
      return result;
    } finally { try { if (paused) await reconnect(); } catch { log.add('브리지 복구 대기'); } busy=false; progress(''); }
  }
  return {manage, history:records.list, menu:{label:'기기 펌웨어',submenu:[
    {label:'키버스-펌웨어 0.4.4 설치…',click:()=>manage('install')},
    {label:'키버스 펌웨어 업데이트…',click:()=>manage('update')},
    {label:'기기 공장 초기화…',click:()=>manage('reset')},
    {label:'정품 Universal Agent로 롤백…',click:()=>manage('rollback')}
  ]}};
}
module.exports = {firmwareControls};
