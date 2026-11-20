'use strict';
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),{randomUUID}=require('node:crypto');
const events=['SessionStart','UserPromptSubmit','PreToolUse','PostToolUse','PostToolUseFailure','Notification','Stop','StopFailure','SessionEnd','PermissionRequest'];
const quote=s=>"'"+s.replaceAll("'","'\\''")+"'";
const owned=hook=>hook?.type==='command' && typeof hook.command==='string' && hook.command.endsWith(' --claude-hook # keyberth');
let busy=false;
async function configure(helper,enabled,folder=path.join(os.homedir(),'.claude')){
  if(busy)throw Error('Claude 훅 설정을 처리 중입니다.');
  busy=true;
  try{
    const file=path.join(folder,'settings.json');
    const read=async()=>{try{return await fs.readFile(file,'utf8');}catch(e){if(e.code==='ENOENT')return null;throw e;}};
    const original=await read();if(!original&&!enabled)return;
    const doc=original===null?{}:JSON.parse(original);
    if(!doc||typeof doc!=='object'||Array.isArray(doc))throw Error('Claude 설정 형식을 확인하세요.');
    doc.hooks??={};
    if(typeof doc.hooks!=='object'||Array.isArray(doc.hooks))throw Error('Claude 훅 설정 형식을 확인하세요.');
    for(const event of events){
      const groups=doc.hooks[event]??[];
      if(!Array.isArray(groups))throw Error('Claude 훅 목록을 확인하세요.');
      const next=groups.flatMap(group=>{
        if(!Array.isArray(group?.hooks)||!group.hooks.some(owned))return [group];
        const hooks=group.hooks.filter(h=>!owned(h));return hooks.length?[{...group,hooks}]:[];
      });
      if(enabled)next.push({hooks:[{type:'command',command:quote(helper)+' --claude-hook # keyberth',timeout:65}]});
      if(next.length)doc.hooks[event]=next;else delete doc.hooks[event];
    }
    const out=JSON.stringify(doc,null,2)+'\n';
    if(out===original)return;
    await fs.mkdir(folder,{recursive:true,mode:0o700});
    const tmp=file+'.'+randomUUID()+'.tmp';
    try{
      await fs.writeFile(tmp,out,{flag:'wx',mode:0o600});
      if(await read()!==original)throw Error('Claude 설정이 변경됐습니다. 다시 시도하세요.');
      await fs.rename(tmp,file);
    }finally{await fs.rm(tmp,{force:true});}
  }finally{busy=false;}
}
module.exports={configure};
