const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {randomUUID} = require('node:crypto');

function history(app) {
  const dir = path.join(app.getPath('userData'),'firmware-history');
  const files = () => fs.existsSync(dir) ? fs.readdirSync(dir).filter(n=>/^\d+-[a-f0-9-]+\.jsonl$/.test(n)).sort().reverse() : [];
  function begin(action) {
    fs.mkdirSync(dir,{recursive:true,mode:0o700});
    const id=randomUUID(), file=path.join(dir,Date.now()+'-'+id+'.jsonl');
    function add(stage,details={}) {
      fs.appendFileSync(file,JSON.stringify({time:Date.now()/1000,stage,...details})+'\n',{mode:0o600});
    }
    add('작업 요청',{id,action,app:app.getVersion(),macOS:process.getSystemVersion?.(),macOSKernel:os.release(),arch:process.arch,target:'0.4.5'});
    for(const old of files().slice(50)) fs.unlinkSync(path.join(dir,old));
    return {id,file,add,read:()=>read(file)};
  }
  function list() {
    return files().map(name=>read(path.join(dir,name))).filter(record=>record.length);
  }
  function read(file) {
      const lines=fs.readFileSync(file,'utf8').trim().split('\n');
      return lines.flatMap(line=>{try{return [JSON.parse(line)];}catch{return [];}});

  }
  return {begin,list};
}
module.exports={history};
