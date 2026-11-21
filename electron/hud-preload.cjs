const { ipcRenderer } = require('electron');
const layout = ['dial','K01','K02','stick','K03','K04','K05','K06','K07','K08','K09','K10','touch','K11','K12','K13'];
const symbols = {ENC_CCW:'↶',ENC_PRESS:'●',ENC_CW:'↷',JOY_UP:'↑',JOY_LEFT:'←',JOY_RIGHT:'→',JOY_DOWN:'↓'};
const keyName = key => symbols[key] || String(Number(key.slice(1)));
ipcRenderer.on('hud', (_, message) => {
  const keys = message.keys || [];
  const pad = document.getElementById('pad'), legend = document.getElementById('legend');
  pad.hidden = !keys.length;
  document.body.classList.toggle('guide',!!keys.length);
  document.getElementById('title').textContent = message.subtitle;
  pad.replaceChildren(); legend.replaceChildren();
  if (!keys.length) return;
  const changed = new Set(keys.map(item=>item.key));
  function cap(key) {
    const el=document.createElement('b');
    el.textContent=keyName(key);
    if(changed.has(key)) el.className='changed';
    return el;
  }
  for (const id of layout) {
    if(id.startsWith('K')) { pad.append(cap(id)); continue; }
    const cell=document.createElement('div'); cell.className=id;
    const parts=id==='dial'?['ENC_CCW','ENC_PRESS','ENC_CW']:id==='stick'?['JOY_UP','JOY_LEFT','JOY_RIGHT','JOY_DOWN']:[];
    for(const key of parts)cell.append(cap(key));
    pad.append(cell);
  }
  // Prefer numbered action keys over a run of adjacent session slots.
  const ranked=[...keys].sort((a,b)=>priority(a)-priority(b));
  function priority(item){return (item.name==='미할당'?4:0)+(/^K(?:0[7-9]|1[0-3])$/.test(item.key)?0:/^K/.test(item.key)?2:1);}
  for(const {key,name} of ranked.slice(0,3)){
    const row=document.createElement('div'),number=document.createElement('kbd'),text=document.createElement('span');
    number.textContent=keyName(key); text.textContent=name;row.append(number,text);legend.append(row);
  }
});
