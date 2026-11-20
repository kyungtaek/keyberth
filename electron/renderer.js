'use strict';
const $ = id => document.getElementById(id);
const api = window.keyberth.command;
const query = new URLSearchParams(location.search);
const popup = query.get('popup') === 'true';
document.body.classList.toggle('popup', popup);
let categoryOverride = '';
let view = query.get('view') || 'mapping';
let catalog, state, selected = 'K07', prefs, prefsBusy = false, polling = false, noticeTimer;
const drafts = new Map();
const byId = new Map(), buttons = new Map(), slotButtons = [];
function announce(message) {
  $('notice').textContent = message;
  clearTimeout(noticeTimer);
  noticeTimer = setTimeout(() => { $('notice').textContent = ''; }, 4500);
}
function fail(error) { announce(error.message.replace(/^Error invoking remote method 'command': Error: /, '')); }
function button(text, cls, click) {
  const b = document.createElement('button');
  b.textContent = text; b.className = cls; b.onclick = click;
  return b;
}
function group(cls) {
  const node = document.createElement('div');
  node.className = cls;
  return node;
}
const fixed = {ENC_CW:'다음 키맵', ENC_CCW:'이전 키맵', ENC_PRESS:'자동 전환 켬/끔'};
function draftKey() { return state.profile + '/' + selected; }
function binding(id) { return state.mappings[id] || id; }
const notePrefix = 'obsidian-note:';
const noteTitle = value => value.slice(notePrefix.length).split('/').pop().replace(/\.md$/i,'');
const desktopFunctions = [
  ['cmd+c','복사'],['cmd+v','붙여넣기'],['cmd+x','잘라내기'],['cmd+f','찾기'],['cmd+a','전체 선택'],
  ['cmd+z','실행 취소'],['cmd+shift+z','다시 실행'],['escape','취소 / 닫기'],['space','공백 입력'],['enter','엔터 입력'],
  ['left','왼쪽 이동'],['right','오른쪽 이동'],['up','위로 이동'],['down','아래로 이동']
];
let availableFunctions = new Map();
function actionText(value) {
  if(value.startsWith(notePrefix)) return noteTitle(value);
  return availableFunctions.get(value) || (state.profile==='cmux' && byId.get(value)?.action) || '사용자 단축키';
}
const actionIcons = {
  K07: 'workspace', K08: 'approve', K09: 'deny', K10: 'sidebar',
  K11: 'space', K12: 'fork', K13: 'enter', ENC_CCW: 'ccw', ENC_CW: 'cw',
  ENC_PRESS: 'unassigned', JOY_UP: 'up', JOY_DOWN: 'down', JOY_LEFT: 'left', JOY_RIGHT: 'right'
};
function graphic(name) {
  const img = document.createElement('img');
  img.src = 'assets/' + name + '.svg';
  img.alt = '';
  img.draggable = false;
  return img;
}
function createKey(id, icon) {
  const number = id.startsWith('K');
  const b = button('', number ? 'cap' : 'smallKey', () => { selected = id; categoryOverride = ''; renderMapping(); });
  b.dataset.control = id;
  if (number) {
    const num = document.createElement('span'), label = document.createElement('span');
    num.className = 'keyNum'; num.textContent = id.slice(1);
    label.className = 'capLabel';
    b.append(num, graphic('session'), label);
  } else if (icon) b.append(graphic(icon));
  buttons.set(id, b);
  return b;
}
function build() {
  for (const profile of catalog.profiles) $('profile').add(new Option(profile.name,profile.id));
  for (const item of catalog.controls) byId.set(item.id, item);
  const dial = group('dial'), joy = group('joy');
  dial.append(createKey('ENC_PRESS'),createKey('ENC_CCW','ccw'),createKey('ENC_CW','cw'));
  for (const id of ['UP','LEFT','RIGHT','DOWN']) joy.append(createKey('JOY_'+id,id.toLowerCase()));
  const key = n => createKey('K'+String(n).padStart(2,'0'));
  $('board').append(dial,key(1),key(2),joy);
  for (let n=3;n<=13;n++) { if(n===11) $('board').append(group('indicator')); $('board').append(key(n)); }
  $('base').add(new Option('키 선택',''));
  for (const [label, keys] of [['특수 키',catalog.special],['문자·숫자',[...'abcdefghijklmnopqrstuvwxyz0123456789']]]) {
    const g=document.createElement('optgroup'); g.label=label;
    for(const k of keys) g.append(new Option(k.toUpperCase(),k));
    $('base').append(g);
  }
  for(const m of ['cmd', ...catalog.modifiers]) {
    const b=button({cmd:'⌘ Cmd',ctrl:'⌃ Ctrl',alt:'⌥ Alt',shift:'⇧ Shift'}[m],'',()=>{
      const d=draft(); d.mods=d.mods.includes(m)?d.mods.filter(v=>v!==m):[...d.mods,m]; renderMapping();
    });
    b.dataset.mod=m; $('mods').append(b);
  }
  for(let i=0;i<6;i++) {
    const b=button('','slot',async()=>{try {await api('select',{target:b.dataset.target,profile:state.profile});} catch(e){fail(e);}});
    const num=document.createElement('span'); num.className='slotIndex';num.textContent=String(i+1).padStart(2,'0');
    b.append(num,document.createElement('b'),document.createElement('small'));$('slots').append(b);slotButtons.push(b);
  }
}
function buildFunctions(profile) {
  let groups;
  if(profile==='cmux') {
    groups=[
      ['워크스페이스 · 대화',['K07','K10','K12','K08','K09']],
      ['세션',['K01','K02','K03','K04','K05','K06','ENC_CCW','ENC_CW']],
      ['패널 이동',['JOY_UP','JOY_DOWN','JOY_LEFT','JOY_RIGHT']],
      ['키 입력 · 기타',['K11','K13','ENC_PRESS']]
    ].map(([name, ids])=>[name,ids.map(id=>[id,byId.get(id).action])]);
  } else {
    groups=[];
    const actions=Object.entries(catalog.agentActions[profile] || {}).sort(([a],[b])=>a.localeCompare(b));
    if(actions.length) groups.push(['최근 세션',actions.filter(([id])=>id.startsWith('recent.'))]);
    if(actions.some(([id])=>id.startsWith('agent.'))) groups.push(['대화 제어',actions.filter(([id])=>id.startsWith('agent.'))]);
    if(profile==='slack') groups.push(['Slack', catalog.slackActions.map(x=>[x.id,x.name])]);
    if(profile==='obsidian') groups.push(['Obsidian', [['cmd+o','빠른 전환'],['cmd+p','명령 팔레트'],['cmd+n','새 노트']]]);
    groups.push(['편집 · 이동', desktopFunctions], ['기타',[['none','미할당']]]);
  }
  availableFunctions=new Map(groups.flatMap(([,entries])=>entries));
  $('category').replaceChildren(); $('actionList').replaceChildren();
  for(const [title,entries] of groups) {
    $('category').add(new Option(title,title));
    for(const [id,label] of entries) {
      const choice=button(label,'choice',()=>{draft().action=id;renderMapping();});
      choice.dataset.id=id;choice.dataset.category=title;$('actionList').append(choice);
    }
  }
}
function fromBinding(value) {
  const note=value.startsWith(notePrefix), action=availableFunctions.has(value);
  const parts=note||action?[]:value.split('+');
  return {mode:note?'note':action?'action':'chord',action:action?value:(state.profile==='cmux'?selected:'none'),
    note:note?value:'',base:parts.pop()||'',mods:parts};

}
function draft() {
  if(!drafts.has(draftKey())) drafts.set(draftKey(),fromBinding(binding(selected)));
  return drafts.get(draftKey());
}
function renderMapping() {
  const saved=binding(selected), d=drafts.get(draftKey())||fromBinding(saved);
  for(const [id,b] of buttons) {
    const title=byId.get(id).name+' · '+(fixed[id] || actionText(binding(id)));
    b.title=title; b.setAttribute('aria-label',title);b.setAttribute('aria-pressed',String(id===selected));
    if (id.startsWith('K')) {
      const assigned = binding(id);
      b.style.removeProperty('--session-color');
      const icon = actionIcons[assigned] || (byId.has(assigned) ? 'session' : 'shortcut');
      b.querySelector('img').setAttribute('src', 'assets/' + icon + '.svg');
      b.querySelector('.capLabel').textContent = actionText(assigned);
      if (assigned.startsWith('recent.')) {
        const slot=state.slots[Number(assigned.slice(7))-1];
        if(slot?.target) {
          b.querySelector('.capLabel').textContent=slot.title;
          b.title+=' · '+slot.title+' · '+slot.state;
          b.setAttribute('aria-label',b.title);
          b.dataset.led=slot.led;
          if(slot.lightColor)b.style.setProperty('--session-color',slot.lightColor);
        } else delete b.dataset.led;
      } else delete b.dataset.led;
      if (assigned.startsWith(notePrefix)) b.title += ' · '+assigned.slice(notePrefix.length);
    }
  }
  $('keyTitle').textContent=selected.startsWith('K')?Number(selected.slice(1))+'번 키':byId.get(selected).name;
  $('keyId').textContent=selected;$('current').textContent=actionText(saved);
  const locked = !!fixed[selected], desktop = state.profile !== 'cmux';
  $('actionMode').parentElement.hidden=locked;
  $('current').textContent=locked ? fixed[selected] : actionText(saved);
  $('noteMode').hidden=!(state.profile==='obsidian' && /^K0[1-6]$/.test(selected));
  $('noteFields').hidden=locked || d.mode!=='note';
  if(locked){
    $('actionFields').hidden=$('chordFields').hidden=true;
    $('save').disabled=$('restore').disabled=true;
    return;
  }
  $('actionMode').textContent='기능';
  $('noteTitle').textContent=d.note?noteTitle(d.note):'문서를 선택하세요';
  $('noteTitle').title=d.note?.slice(notePrefix.length)||'';
  $('noteMode').setAttribute('aria-pressed',String(d.mode==='note'));
  const chord=d.mode==='chord';
  $('actionMode').setAttribute('aria-pressed',String(d.mode==='action'));$('chordMode').setAttribute('aria-pressed',String(chord));
  $('actionFields').hidden=d.mode!=='action';$('chordFields').hidden=!chord;
  const choices = [...$('actionList').children];
  const category = categoryOverride || choices.find(b => b.dataset.id === d.action)?.dataset.category;
  $('category').value = category;
  for (const choice of choices) {
    choice.hidden = choice.dataset.category !== category;
    choice.setAttribute('aria-pressed', String(choice.dataset.id === d.action));
  }
  $('base').value=d.base;
  for(const b of $('mods').children) { b.hidden=b.dataset.mod==='cmd'&&!desktop; b.setAttribute('aria-pressed',String(d.mods.includes(b.dataset.mod))); }
  const combination=[...['cmd',...catalog.modifiers].filter(m=>d.mods.includes(m)),d.base].join('+');
  const valid=d.base && (desktop || catalog.special.includes(d.base)||d.mods.length);
  $('chord').textContent=!d.base?'':valid?combination:'문자·숫자에는 보조 키를 선택하세요.';
  const value=chord?combination:d.mode==='note'?d.note:d.action;
  $('save').disabled=!value || value===saved || (chord && !valid);$('save').dataset.value=value;
  $('restore').disabled=value===state.defaults[selected];
}
function renderState(next) {
  const mappingsChanged = !state || JSON.stringify(next.slots)!==JSON.stringify(state.slots) || next.profile!==state.profile || JSON.stringify(state.mappings) !== JSON.stringify(next.mappings);
  if(state?.profile!==next.profile) {categoryOverride='';buildFunctions(next.profile);}
  state=next; $('profile').value=next.profile; $('activeName').textContent=catalog.profiles.find(p=>p.id===next.profile).name;
  $('auto').textContent='자동 전환 '+(next.automatic?'켬':'끔'); $('auto').setAttribute('aria-pressed',String(next.automatic));
  $('usb').textContent=next.usb;$('cmux').textContent=next.cmux;
  $('usb').title=next.usb;$('cmux').title=next.cmux;
  $('connect').disabled=next.busy;
  $('lightStatus').textContent=next.lightingStatus;
  for(const [i,s] of next.slots.entries()){
    const b=slotButtons[i];b.dataset.target=s.target;b.disabled=!s.target||next.busy;
    b.children[1].textContent=s.title||'빈 슬롯';b.children[2].textContent=s.state;b.children[2].dataset.led=s.led;
    b.title=s.title;
    b.children[0].classList.toggle('coloredSlot',!!s.lightColor);
    b.children[0].style.setProperty('--slot-dot',s.lightColor || 'transparent');
  }
  if(mappingsChanged) renderMapping();
}
async function poll() {
  if(polling||!catalog)return;polling=true;
  try {const next=await api('state');if(next.feedback && state?.feedback!==next.feedback)announce(next.feedback);renderState(next);}
  catch(e){$('usb').textContent='서비스 연결 실패';fail(e);}finally{polling=false;}
}
let lightRules;
let savingLight = false;
const lightDrafts = new Map();
const lightInputs = {};
const effects = ['끄기','고정','흐르기','무지개','숨쉬기','그라데이션','은은한 숨쉬기'];
for(const [zone,title] of [['slot','슬롯 LED'],['ambient','바닥 조명']]) {
  const row=group('lightRow'), label=document.createElement('strong');
  const color=document.createElement('input'), effect=document.createElement('select');
  label.textContent=title; color.type='color';
  color.setAttribute('aria-label',title+' 색상'); effect.setAttribute('aria-label',title+' 애니메이션');
  effects.forEach((text,i)=>effect.add(new Option(text,String(i))));
  color.oninput=effect.onchange=()=>{
    if(!lightRules)return;
    const key=$('lightState').value;
    const rule=lightDrafts.get(key) || structuredClone(lightRules[key]);
    rule[zone]={color:color.value.toUpperCase(),effect:Number(effect.value)};
    lightDrafts.set(key,rule); $('saveLight').disabled=savingLight;
  };
  lightInputs[zone]={color,effect};row.append(label,color,effect);$('lightZones').append(row);
}
function renderLights() {
  const key=$('lightState').value, rule=lightDrafts.get(key) || lightRules[key];
  for(const [zone,inputs] of Object.entries(lightInputs)){
    inputs.color.value=rule[zone].color;inputs.effect.value=rule[zone].effect;
  }
  $('saveLight').disabled=savingLight;
}
async function loadLights(){
  lightRules=(await api('readLighting')).rules;
  $('lightState').replaceChildren(...Object.keys(lightRules).sort().map(name=>new Option(name,name)));
  renderLights();
}
$('lightState').onchange=renderLights;
$('saveLight').onclick=async()=>{
  if(savingLight)return;
  const key=$('lightState').value, rule=structuredClone(lightDrafts.get(key)||lightRules[key]);
  savingLight=true;renderLights();
  try {
    lightRules=(await api('saveLighting',{lightState:key,rule})).rules;
    if(JSON.stringify(lightDrafts.get(key))===JSON.stringify(rule))lightDrafts.delete(key);
    announce('조명 설정을 이 Mac에 저장했습니다.');
  } catch(e){fail(e);} finally{savingLight=false;renderLights();}
};
function updatePrefsButtons(){
  const n=$('sleep').valueAsNumber;
  $('sleep').disabled=$('volume').disabled=!prefs||prefsBusy;
  $('readPrefs').disabled=prefsBusy;
  $('volumeText').textContent=$('volume').value+'%';
  $('savePrefs').disabled=!prefs||prefsBusy||!Number.isInteger(n)||n<0||n>120||(n===prefs.sleep && +$('volume').value===prefs.volume);
}
async function device(save){
  if(prefsBusy)return;prefsBusy=true;updatePrefsButtons();
  try{
    prefs=await api(save?'savePrefs':'readPrefs',save?{revision:prefs.revision,sleep:$('sleep').valueAsNumber,volume:+$('volume').value}:{});
    $('sleep').value=prefs.sleep;$('volume').value=prefs.volume;$('buzzer').textContent=prefs.buzzer?'':'기기의 부저 스위치가 꺼져 있습니다.';
    if(save)announce('기기에서 저장된 값을 확인했습니다.');
  }catch(e){prefs=null;$('buzzer').textContent=e.message;}
  finally{prefsBusy=false;updatePrefsButtons();}
}
$('profile').onchange=async e=>{try{renderState(await api('activateProfile',{profile:e.target.value}));}catch(err){fail(err);}};
$('auto').onclick=async()=>{try{renderState(await api('toggleAuto'));}catch(err){fail(err);}};
function show(name){
  view=name;
  for(const v of ['mapping','sessions','device']) $(v).hidden=v!==view;
  for(const b of document.querySelectorAll('[data-view]')) {
    if(b.dataset.view===view)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');
  }
  if(view==='device'&&!prefs)device(false);
  if(view==='device'&&!lightRules)loadLights().catch(fail);
}
for(const b of document.querySelectorAll('[data-view]'))b.onclick=()=>show(b.dataset.view);
$('openEditor').onclick=()=>popup?api('editor',{view:'mapping'}):show('mapping');
$('noteMode').onclick=()=>{draft().mode='note';renderMapping();};
$('chooseNote').onclick=async()=>{
  const key=draftKey(), d=draft();
  try {
    const value=await api('chooseNote');
    if(value){d.mode='note';d.note=value;drafts.set(key,d);renderMapping();}
  }catch(error){fail(error);}
};
$('actionMode').onclick=()=>{draft().mode='action';renderMapping();};
$('chordMode').onclick=()=>{draft().mode='chord';renderMapping();};
$('category').onchange=e=>{categoryOverride=e.target.value;renderMapping();};
$('base').onchange=e=>{draft().base=e.target.value;renderMapping();};
$('restore').onclick=()=>{categoryOverride=''; drafts.set(draftKey(),fromBinding(state.defaults[selected]));renderMapping();};
$('save').onclick=async()=>{
  const input=selected, profile=state.profile, key=draftKey();
  try{const next=await api('save',{input,profile,binding:$('save').dataset.value});drafts.delete(key);renderState(next);announce('매핑을 저장했습니다.');}
  catch(e){fail(e);}
};
document.addEventListener('keydown',e=>{if(e.metaKey&&e.key==='s'){e.preventDefault();if(view==='mapping')$('save').click();else if(view==='device')$('savePrefs').click();}});
$('volume').oninput=$('sleep').oninput=updatePrefsButtons;
$('readPrefs').onclick=()=>device(false);$('savePrefs').onclick=()=>device(true);
$('connect').onclick=()=>api('connect').catch(fail);
window.keyberth.onView(show);
(async()=>{catalog=await api('catalog');build();await poll();show(view);setInterval(()=>{if(!document.hidden)poll();},900);document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll();});})().catch(fail);
