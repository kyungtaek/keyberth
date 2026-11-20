'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),{randomUUID}=require('node:crypto');
const filters=[{name:'Keyberth 키맵',extensions:['json']}];
async function transfer(method,editor,dialog,request) {
  if(method==='exportMaps'){
    const {canceled,filePath}=await dialog.showSaveDialog(editor,{title:'키맵 내보내기',defaultPath:'Keyberth-keymaps.json',filters});
    if(canceled||!filePath)return null;
    const archive=await request('exportMaps');
    const tmp=path.join(path.dirname(filePath),'.keyberth-'+randomUUID()+'.tmp');
    try {
      await fs.writeFile(tmp,JSON.stringify(archive,null,2)+'\n',{flag:'wx',mode:0o600});
      await fs.rename(tmp,filePath);
    }finally{await fs.rm(tmp,{force:true});}
    return true;
  }
  const pick=await dialog.showOpenDialog(editor,{title:'키맵 가져오기',filters,properties:['openFile']});
  if(pick.canceled||!pick.filePaths.length)return null;
  const file=await fs.open(pick.filePaths[0],'r');
  let archive;
  try{
    const buf=Buffer.alloc(256*1024+1);
    const stat=await file.stat();
    if(!stat.isFile()||stat.size>=buf.length)throw Error('256KB 이하인 JSON 파일을 선택하세요.');
    let n=0;
    while(n<buf.length){const {bytesRead}=await file.read(buf,n,buf.length-n,null);if(!bytesRead)break;n+=bytesRead;}
    if(n===buf.length)throw Error('파일이 너무 큽니다.');
    archive=JSON.parse(buf.toString('utf8',0,n));
  }finally{await file.close();}
  if(archive?.version!==1 || !archive.profiles || Array.isArray(archive.profiles) || typeof archive.profiles!=='object' ||
    !Object.keys(archive.profiles).length || !Object.values(archive.profiles).every(map=>map && typeof map==='object' && !Array.isArray(map) && Object.values(map).every(v=>typeof v==='string')))throw Error('지원하지 않는 키맵 파일입니다.');
  const confirm=await dialog.showMessageBox(editor,{message:'파일에 포함된 프로필의 키맵을 교체할까요?',detail:Object.keys(archive.profiles).join(', '),buttons:['가져오기','취소'],defaultId:0,cancelId:1});
  return confirm.response===0 ? request('importMaps',{archive}) : null;
}
module.exports={transfer};
