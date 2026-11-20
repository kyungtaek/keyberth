'use strict';
const { app, autoUpdater, dialog } = require('electron');
const { spawnSync } = require('node:child_process');
const path = require('node:path');

function configureUpdates(beforeInstall) {
  const bundle = path.resolve(process.execPath,'../../..');
  const signed = app.isPackaged && process.platform === 'darwin' &&
    /Authority=Developer ID Application:/.test(spawnSync('/usr/bin/codesign',['-dv','--verbose=4',bundle],{encoding:'utf8'}).stderr || '');
  let busy=false, manual=false, downloaded=false;
  const inform=(message,detail='')=>dialog.showMessageBox({type:'info',message,detail,buttons:['확인']});
  async function install() {
    const {response}=await dialog.showMessageBox({type:'info',message:'Keyberth 업데이트가 준비되었습니다.',buttons:['재시작하고 설치','나중에'],defaultId:0,cancelId:1});
    if(response===0) autoUpdater.quitAndInstall();
  }
  function check(user=false) {
    if(!signed || bundle.startsWith('/Volumes/') || bundle.includes('/AppTranslocation/')) {
      if(user) void inform('응용 프로그램에 설치된 서명 배포본에서 업데이트를 확인하세요.');
      return;
    }
    if(downloaded){ if(user) void install(); return; }
    if(user) manual=true;
    if(busy)return;
    busy=true;
    try { autoUpdater.checkForUpdates(); }
    catch(error){ busy=false;manual=false;if(user) void inform('업데이트 확인 실패',error.message); }
  }
  if(signed){
    autoUpdater.on('before-quit-for-update',beforeInstall);
    autoUpdater.setFeedURL({url:'https://github.com/kyungtaek/keyberth/releases/latest/download/releases-'+process.arch+'.json',serverType:'json'});
    autoUpdater.on('error',error=>{busy=false;if(manual)void inform('업데이트 확인 실패',error.message);manual=false;});
    autoUpdater.on('update-not-available',()=>{busy=false;if(manual)void inform('현재 최신 버전입니다.',app.getVersion());manual=false;});
    autoUpdater.on('update-downloaded',()=>{busy=false;manual=false;downloaded=true;void install();});
    const first=setTimeout(()=>check(),15000), every=setInterval(()=>check(),6*60*60*1000);
    app.once('will-quit',()=>{clearTimeout(first);clearInterval(every);});
  }
  return ()=>check(true);
}
module.exports = {configureUpdates};
