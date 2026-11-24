'use strict';
const $ = id => document.getElementById(id);
const api = window.keyberth.command;
const query = new URLSearchParams(location.search);
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
// All editors use the same change handler for pointer, keyboard and restored values.
function buildPicker(select, container) {
  container.replaceChildren();
  let lastGroup, row=container;
  for (const option of select.options) {
    if (!option.value) continue;
    const part=option.parentElement;
    if(part.tagName==='OPTGROUP' && part!==lastGroup) {
      const label=document.createElement('h3'); label.textContent=part.label;
      row=group('keyGrid'); container.append(label,row); lastGroup=part;
    }
    const item=button(option.textContent,'pick',()=>{
      select.value=option.value; select.dispatchEvent(new Event('change'));
    });
    item.dataset.value=option.value;
    row.append(item);
  }
  syncPicker(select,container);
}
function syncPicker(select,container) {
  for(const item of container.querySelectorAll('button')) {
    item.disabled=select.disabled;
    item.setAttribute('aria-pressed',String(item.dataset.value===select.value));
  }
}
function globalEdit() { return $('scope').value==='global'; }
let editProfile='', applyingPreset=false;
function overrides(){return state?.appOverrides?.[editProfile] || {};}
function hasOverride(id){return Object.hasOwn(overrides(),id) && overrides()[id]!=='inherit';}
function draftKey() { return (globalEdit()?'global':editProfile) + '/' + selected; }
function binding(id) { return !globalEdit() && hasOverride(id) ? overrides()[id] : state.globalMappings?.[id] || 'none'; }
const notePrefix = 'obsidian-note:';
const noteTitle = value => value.slice(notePrefix.length).split('/').pop().replace(/\.md$/i,'');
const desktopFunctions = [
  ['cmd+b','사이드바'],['ctrl+cmd+f','전체 화면'],['cmd+=','글자 확대'],['cmd+-','글자 축소'],['ctrl+shift+tab','이전 대화'],['ctrl+tab','다음 대화'],['backspace','한 글자 삭제'],['cmd+d','Claude 음성'],['cmd+n','새 대화'],['shift+enter','줄바꿈'],['cmd+c','복사'],['cmd+v','붙여넣기'],['cmd+x','잘라내기'],['cmd+f','찾기'],['cmd+a','전체 선택'],
  ['cmd+z','실행 취소'],['cmd+shift+z','다시 실행'],['escape','취소 / 닫기'],['space','공백 입력'],['enter','엔터 입력'],
  ['left','왼쪽 이동'],['right','오른쪽 이동'],['up','위로 이동'],['down','아래로 이동']
];
const appMenus = new Map();
const menuProfiles = new Set(['codex','t3','cmux']);
let availableFunctions = new Map();
let runningApps = {};
function storedActionLabel(id) {
  if (id.startsWith('menu:')) {
    try {return JSON.parse(id.slice(5)).join(' › ');} catch {return id;}
  }
  if (id.startsWith('launch.')) return (catalog.favorites[id.slice(7)] || id.slice(7))+' 열기';
  return '';
}
async function readMenus(profile) {
  if (!menuProfiles.has(profile)) return;
  try {
    const menus = await api('appMenus',{profile});
    appMenus.set(profile,menus);
    if (!globalEdit() && editProfile===profile) { buildFunctions(profile); renderMapping(); }
  } catch(error) { fail(error); }
}
function fillFavoritePicker() {
  const picker=$('favoriteApp'), selected=picker.value;
  picker.replaceChildren(new Option('응용 프로그램 파일 선택…',''));
  for(const [title,apps] of [['즐겨찾기',catalog.favorites],['실행 중',runningApps]]) {
    const group=document.createElement('optgroup');group.label=title;
    for(const [id,name] of Object.entries(apps).sort((a,b)=>a[1].localeCompare(b[1]))) {
      if(title==='실행 중' && id in catalog.favorites) continue;
      group.append(new Option(name,id));
    }
    if(group.children.length) picker.append(group);
  }
  picker.value=[...picker.options].some(o=>o.value===selected)?selected:'';
  picker.onchange();
}
async function refreshFavoritePicker() {
  try {runningApps=await api('runningApps');fillFavoritePicker();} catch(error) {fail(error);}
}

function actionText(value,profile=editProfile) {
  if(value.startsWith(notePrefix)) return noteTitle(value);
  return catalog.agentActions[profile]?.[value] || availableFunctions.get(value) || storedActionLabel(value) || (profile==='cmux' && byId.get(value)?.action) || '사용자 단축키';
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
function capMaterial(id) {
  const saved=localStorage.getItem('keyberth.cap.'+id);
  if(saved==='clear'||saved==='opaque')return saved;
  return /^K(0[1-6]|13)$/.test(id)?'clear':'opaque';
}
$('capMaterial').onchange=()=>{
  if(!/^K(0[1-9]|1[0-3])$/.test(selected))return;
  const value=$('capMaterial').value;
  localStorage.setItem('keyberth.cap.'+selected,value);
  buttons.get(selected).dataset.material=value;
};
let previewKey='K01';
let liveSlots=[];
function simulating() { return view==='device' && !$('lighting').hidden; }
function createKey(id, icon) {
  const number = id.startsWith('K');
  const b = button('', number ? 'cap' : 'smallKey', () => {
    if(simulating()) {previewKey=id; renderPreview();return;}
    if(view==='sessions') {slotButtons[Number(id.slice(1))-1]?.click();return;}
    selected=id;categoryOverride='';renderMapping();
  });
  b.dataset.control = id;
  if (number) {
    b.dataset.material=capMaterial(id);
    const num = document.createElement('span'), label = document.createElement('span');
    num.className = 'keyNum'; num.textContent = id.slice(1);
    label.className = 'capLabel';
    const lamp=group('lamp');lamp.setAttribute('aria-hidden','true');
    b.append(lamp,num,graphic('session'),label);
  } else if (icon) b.append(graphic(icon));
  buttons.set(id, b);
  return b;
}
function build() {

  for (const item of catalog.controls) byId.set(item.id, item);
  const dial = group('dial'), joy = group('joy');
  dial.append(createKey('ENC_PRESS'),createKey('ENC_CCW','ccw'),createKey('ENC_CW','cw'));
  for (const id of ['UP','LEFT','RIGHT','DOWN']) joy.append(createKey('JOY_'+id,id.toLowerCase()));
  const key = n => createKey('K'+String(n).padStart(2,'0'));
  $('board').append(dial,key(1),key(2),joy);
  for (let n=3;n<=13;n++) { if(n===11) $('board').append(group('indicator')); $('board').append(key(n)); }
  $('base').add(new Option('키 선택',''));
  for (const [label, keys] of [['특수 키',catalog.special],['문자·숫자·기호',[...'abcdefghijklmnopqrstuvwxyz0123456789=-[]']]]) {
    const g=document.createElement('optgroup'); g.label=label;
    for(const k of keys) g.append(new Option(k.toUpperCase(),k));
    $('base').append(g);
  }
  buildPicker($('base'),$('baseGrid'));
  buildPicker($('scope'),$('scopesBar'));
  for(const m of catalog.modifiers) {
    const b=button({cmd:'⌘ Command',ctrl:'⌃ Control',alt:'⌥ Option',shift:'⇧ Shift'}[m],'',()=>{
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
function buildFunctions(profile,currentMappings={...state?.globalMappings,...overrides()}) {
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
    if(actions.some(([id])=>id.startsWith('recent.'))) groups.push(['최근 세션',actions.filter(([id])=>id.startsWith('recent.'))]);
    if(actions.some(([id])=>id.startsWith('agent.'))) groups.push(['대화 제어',actions.filter(([id])=>id.startsWith('agent.') && !id.startsWith('agent.t3.'))]);
    if(profile==='app.com.stablyai.orca') {
      const sections=new Map();
      for(const entry of actions) {
        const group=catalog.orcaGroups[entry[0]];
        if(!sections.has(group)) sections.set(group,[]);
        sections.get(group).push(entry);
      }
      groups.push(...sections);
    }
    if(profile==='t3') groups.push(['T3 명령',actions.filter(([id])=>id.startsWith('agent.t3.') || id==='agent.settle')]);
    if(profile==='slack') groups.push(['Slack', catalog.slackActions.map(x=>[x.id,x.name])]);
    if(profile==='obsidian') groups.push(['Obsidian', [['cmd+o','빠른 전환'],['cmd+p','명령 팔레트'],['cmd+n','새 노트']]]);
    groups.push(['편집 · 이동', desktopFunctions.filter(([id])=>id!=='cmd+d'||profile==='claude')], ['기타',[['none','미할당']]]);
  }
  if(profile==='cmux') groups.unshift(['대화 제어',Object.entries(catalog.agentActions.cmux)]);
  const shared=Array.from({length:6},(_,i)=>['allRecent.'+(i+1),'통합 최근 세션 '+(i+1)]);
  if(globalEdit() || profile==='unconfigured') groups=[['기타',[['none','미할당']]]];
  groups.unshift(['통합 최근 세션',shared]);
  const menus=Object.entries(!globalEdit() && appMenus.get(profile)||{}).sort((a,b)=>a[1].localeCompare(b[1]));
  const byMenu=new Map();
  for(const [id,label] of menus) {
    const [top,...rest]=JSON.parse(id.slice(5));
    if(!byMenu.has(top)) byMenu.set(top,[]);
    byMenu.get(top).push([id,rest.join(' › ')]);
  }
  for(const [top,actions] of byMenu) groups.push(['앱 메뉴 · '+top,actions]);
  groups.push(['대상 앱 지정',Object.entries(catalog.targetActions || {})], ['앱 전환',Object.entries(catalog.favorites).map(([id,name])=>['launch.'+id,name+' 열기'])],
              ['시스템 동작',Object.entries(catalog.systemActions)]);
  const known=new Set(groups.flatMap(([,entries])=>entries.map(([id])=>id)));
  const missing=[...new Set(Object.values(currentMappings))].filter(id=>storedActionLabel(id) && !known.has(id));
  if(missing.length) groups.push(['저장된 배정',missing.map(id=>[id,storedActionLabel(id)])]);
  availableFunctions=new Map(groups.flatMap(([,entries])=>entries));
  $('category').replaceChildren(); $('actionList').replaceChildren();
  for(const [title,entries] of groups) {
    $('category').add(new Option(title,title));
    for(const [id,label] of entries) {
      const needsShortcut=catalog.orcaNeedsShortcut?.includes(id);
      const choice=button(needsShortcut ? label+' · Orca 단축키 지정 필요' : label,'choice',()=>{draft().action=id;renderMapping();});
      choice.dataset.id=id;choice.dataset.category=title;$('actionList').append(choice);
    }
  }
  buildPicker($('category'),$('groupBar'));
}
function fromBinding(value) {
  const note=value.startsWith(notePrefix), action=availableFunctions.has(value);
  const parts=note || !/^(?:(?:cmd|ctrl|alt|shift)\+)*(?:[a-z0-9=\-\[\]]+)$/.test(value) ? [] : value.split('+');
  return {mode:note?'note':action?'action':'chord',action:action?value:(editProfile==='cmux'?selected:'none'),
    note:note?value:'',base:parts.pop()||'',mods:parts};

}
function draft() {
  if(!drafts.has(draftKey())) drafts.set(draftKey(),fromBinding(binding(selected)));
  return drafts.get(draftKey());
}
function defaultForKey() {return globalEdit()?(/^K0[1-6]$/.test(selected)?'allRecent.'+Number(selected.slice(1)):'none'):catalog.appDefaults?.[editProfile]?.[selected] || 'none';}
function renderMapping() {
  const saved=binding(selected), d=drafts.get(draftKey())||fromBinding(saved);
  for(const [id,b] of buttons) {
    const boardProfile=view==='mapping'?editProfile:state.profile;
    const assigned=view==='mapping'?binding(id):state.mappings[id] || 'none';
    const title=byId.get(id).name+' · '+actionText(assigned,boardProfile);
    b.toggleAttribute('data-override',view==='mapping' && !globalEdit() && hasOverride(id));
    b.title=title; b.setAttribute('aria-label',title);b.setAttribute('aria-pressed',String(id===selected));
    if (id.startsWith('K')) {
      b.style.removeProperty('--session-color');
      delete b.dataset.session;
      const icon = actionIcons[assigned] || (byId.has(assigned) ? 'session' : 'shortcut');
      b.querySelector('img').setAttribute('src', 'assets/' + icon + '.svg');
      b.querySelector('.capLabel').textContent = actionText(assigned,boardProfile);
      const shared=/^allRecent\.([1-6])$/.exec(assigned);
      const slotBinding = /^(?:recent\.([1-6])|slack\.K0([1-6]))$/.exec(assigned);
      const cmuxSlot = boardProfile==='cmux' && /^K0[1-6]$/.test(assigned);
      if (shared || slotBinding || cmuxSlot) {
        const index=shared ? Number(shared[1]) : cmuxSlot ? Number(assigned.slice(1)) : Number(slotBinding[1] || slotBinding[2]);
        const slot=(shared ? state.combinedSlots : state.slots)?.[index-1];
        b.dataset.session='true';
        b.querySelector('.capLabel').textContent='최근 세션';
        b.querySelector('img').setAttribute('src','assets/session.svg');
        if(slot?.target) {
          b.title+=' · '+slot.state;
          b.setAttribute('aria-label',b.title);
          b.dataset.led=slot.led;
          if(slot.lightColor)b.style.setProperty('--session-color',slot.lightColor);
        } else delete b.dataset.led;
      } else delete b.dataset.led;
      if (assigned.startsWith(notePrefix)) b.title += ' · '+assigned.slice(notePrefix.length);
    }
  }
  $('keyTitle').textContent=selected.startsWith('K')?Number(selected.slice(1))+'번 키':byId.get(selected).name;
  $('capMaterialField').hidden=!buttons.get(selected)?.dataset.material;
  if(!$('capMaterialField').hidden)$('capMaterial').value=capMaterial(selected);
  $('keyId').textContent=selected;$('current').textContent=actionText(saved);
  const desktop = globalEdit() || editProfile !== 'cmux';
  $('appEditor').hidden=globalEdit();
  $('overrideCount').textContent=editProfile ? '예외 키 '+Object.keys(overrides()).filter(hasOverride).length+'개' : '';
  const presetKeys=Object.keys(catalog.presets?.[editProfile] || {});
  const available=presetKeys.filter(key=>!Object.hasOwn(overrides(),key)).length;
  $('applyPreset').hidden=globalEdit() || !presetKeys.length;
  $('applyPreset').disabled=applyingPreset || !available;
  $('applyPreset').textContent=available?'프리셋 적용 · '+available+'개':'프리셋 적용할 키 없음';
  $('inherit').hidden=globalEdit();
  $('inherit').disabled=!hasOverride(selected);
  $('current').previousElementSibling.textContent=globalEdit()?'글로벌 배정':hasOverride(selected)?'앱 배정':'글로벌에서 상속';

  $('current').textContent=actionText(saved);
  $('noteMode').hidden=!( !globalEdit() && editProfile==='obsidian' && /^K0[1-6]$/.test(selected));
  $('noteFields').hidden=d.mode!=='note';
  $('reloadMenus').hidden=globalEdit() || !menuProfiles.has(editProfile);
  $('actionMode').textContent='기능';
  $('noteTitle').textContent=d.note?noteTitle(d.note):'문서를 선택하세요';
  $('noteTitle').title=d.note?.slice(notePrefix.length)||'';
  $('noteMode').setAttribute('aria-pressed',String(d.mode==='note'));
  const chord=d.mode==='chord';
  $('actionMode').setAttribute('aria-pressed',String(d.mode==='action'));$('chordMode').setAttribute('aria-pressed',String(chord));
  $('actionFields').hidden=d.mode!=='action';$('chordFields').hidden=!chord;
  const choices = [...$('actionList').children];
  const category = categoryOverride || choices.find(b => b.dataset.id === d.action)?.dataset.category || $('category').options[0]?.value;
  $('category').value = category;
  $('manageFavorites').hidden=category!=='앱 전환';
  for (const choice of choices) {
    const search=$('functionSearch').value.trim().toLocaleLowerCase();
    choice.hidden = search ? !(choice.dataset.category+' '+choice.textContent).toLocaleLowerCase().includes(search) : choice.dataset.category !== category;
    choice.setAttribute('aria-pressed', String(choice.dataset.id === d.action));
  }
  $('noActions').hidden=choices.some(b=>!b.hidden) || !$('manageFavorites').hidden;
  syncPicker($('category'),$('groupBar'));
  syncPicker($('scope'),$('scopesBar'));
  $('base').value=d.base;
  syncPicker($('base'),$('baseGrid'));
  for(const b of $('mods').children) { b.setAttribute('aria-pressed',String(d.mods.includes(b.dataset.mod))); }
  const combination=[...catalog.modifiers.filter(m=>d.mods.includes(m)),d.base].join('+');
  const valid=d.base && (desktop || catalog.special.includes(d.base)||d.mods.length);
  $('chord').textContent=!d.base?'':valid?combination:'문자·숫자에는 보조 키를 선택하세요.';
  const value=chord?combination:d.mode==='note'?d.note:d.action;
  $('save').disabled=(!globalEdit() && !editProfile) || !value || (value===saved && (globalEdit()?state.explicitGlobal?.includes(selected):hasOverride(selected))) || (chord && !valid);$('save').dataset.value=value;
  $('restore').disabled=value===defaultForKey();
  renderPreview();
}
let claudeSignature = '';
function renderClaudeOptions(next) {
  const visible = next.profile === 'claudeCode';
  $('claudeSlots').hidden = !visible;
  const options = next.claudeOptions;
  const signature = visible ? JSON.stringify(options) : '';
  if (signature === claudeSignature) return;
  claudeSignature = signature;
  const fields = $('claudeSlotFields');
  fields.replaceChildren();
  if (!visible) return;
  function select(label, input, current, choices, initial) {
    const row = document.createElement('label'), menu = document.createElement('select');
    row.textContent = label;
    menu.add(new Option(initial,''));
    for (const choice of choices) menu.add(new Option(choice.name,choice.id));
    if (current && !choices.some(x=>x.id === current)) menu.add(new Option('사용할 수 없음',current));
    menu.value = current || '';
    menu.onchange = async () => {
      try { renderState(await api('configureClaude',{input,binding:menu.value})); }
      catch(error){claudeSignature='';renderClaudeOptions(state);fail(error);}
    };
    row.append(menu);fields.append(row);
  }
  select('세션 소스','source',options.source,options.sources.map(id=>({id,name:id})), '전체');
  for(let i=1;i<=6;i++) select('슬롯 '+i,String(i),options.pins[String(i)],options.choices,'최근 활동순');
  if(options.requests.length) select('선택한 세션의 권한 요청','request',options.request,
    options.requests.map(x=>({...x,name:x.name+' · '+x.id.split('.')[1].slice(0,8)})), '단일 요청 자동 선택');
}
function renderState(next) {
  renderClaudeOptions(next);
  const mappingsChanged = !state || JSON.stringify([next.globalMappings,next.localKeys,next.explicitGlobal,next.explicitLocal,next.combinedSlots])!==JSON.stringify([state.globalMappings,state.localKeys,state.explicitGlobal,state.explicitLocal,state.combinedSlots]) || JSON.stringify(next.slots)!==JSON.stringify(state.slots) || next.profile!==state.profile || JSON.stringify(state.mappings) !== JSON.stringify(next.mappings);
  const profilesChanged=!state || JSON.stringify(state.profiles)!==JSON.stringify(next.profiles);
  const assignmentsChanged=!state || JSON.stringify(state.appOverrides)!==JSON.stringify(next.appOverrides);
  if (profilesChanged) {
    if(!next.profiles.some(p=>p.id===editProfile))editProfile='';
    const present=new Set(next.profiles.map(p=>p.id));
    const picker=$('manageProfile'), managementTarget=picker.value;
    picker.replaceChildren(...next.profiles.map(p=>new Option(p.name,p.id)));
    picker.value=present.has(managementTarget)?managementTarget:'';
    $('emptyProfiles').hidden=present.size>0;
    picker.hidden=present.size===0;
    const choice=$('addKeymapChoice'), previous=choice.value;
    choice.replaceChildren(new Option('응용 프로그램 선택…',''),...catalog.templates.filter(p=>!present.has(p.id)).map(p=>new Option(p.name,p.id)));
    if([...choice.options].some(option=>option.value===previous))choice.value=previous;
  }
  state=next; if(profilesChanged) fillProcesses();
  if(profilesChanged || assignmentsChanged)buildFunctions(editProfile);
  $('activeName').textContent=next.profiles.find(p=>p.id===next.profile)?.name || '글로벌';
  $('manageProfile').onchange();
  $('auto').textContent='자동 전환 '+(next.automatic?'켬':'끔'); $('auto').setAttribute('aria-pressed',String(next.automatic));
  $('firmwareConnection').textContent=next.usb || '연결 대기';
  $('usb').textContent=next.usb;$('cmux').textContent=next.cmux;
  $('usb').title=next.usb;$('cmux').title=next.cmux;
  $('connect').disabled=next.busy;
  $('lightStatus').textContent=next.lightingStatus;
  $('firmwareName').textContent=next.usb?.includes('0.4.5-keyberth') ? '키버스-펌웨어 / 0.4.5' : next.usb?.includes('0.4.4-keyberth') ? '키버스-펌웨어 / 0.4.4' : next.usb?.includes('0.4.3-keyberth') ? '키버스-펌웨어 / 0.4.3' : next.usb?.includes('0.4.2-keyberth') ? '키버스-펌웨어 / 0.4.2' : next.usb?.includes('0.4.1-keyberth') ? '키버스-펌웨어 / 0.4.1' : next.usb?.includes('0.4.0-keyberth') ? '키버스-펌웨어 / 0.4.0' : next.usb?.includes('0.3.0-keyberth') ? '키버스-펌웨어 / 0.3.0' : next.usb?.includes('0.2.0-keyberth') ? '키버스-펌웨어 / 0.2.0' : next.usb?.includes('0.1.0-keyberth-dev') ? 'Keyberth USB / 0.1.0-dev' : next.usb?.includes('0.2.18') ? 'Universal Agent / 0.2.18' : 'AI Micro';
  for(const [i,local] of next.slots.entries()){
    const input='K'+String(i+1).padStart(2,'0');
    const value=next.mappings[input] || '';
    const shared=/^allRecent\.([1-6])$/.exec(value);
    const perApp=/^(?:recent\.|K0)([1-6])$/.exec(value);
    const s=shared ? next.combinedSlots[Number(shared[1])-1] || {} : perApp ? next.slots[Number(perApp[1])-1] : next.profile==='slack'?local:{};

    liveSlots[i]=s;
    const b=slotButtons[i];b.dataset.target=s.target||'';b.disabled=!s.target||next.busy;
    b.children[1].textContent=s.title||'빈 슬롯';b.children[2].textContent=s.active?'선택됨 · '+s.state:s.state||'';b.children[2].dataset.led=s.led;
    b.title=s.title;
    b.children[0].classList.toggle('coloredSlot',!!s.lightColor);
    b.children[0].style.setProperty('--slot-dot',s.lightColor || 'transparent');
  }
  if(mappingsChanged || profilesChanged || assignmentsChanged) renderMapping();
}
async function poll() {
  if(polling||!catalog)return;polling=true;
  try {const next=await api('state');if(next.feedback && state?.feedback!==next.feedback)announce(next.feedback);renderState(next);}
  catch(e){$('usb').textContent='서비스 연결 실패';fail(e);}finally{polling=false;}
}
let lightRules;
let savingLight = false;
const lightDrafts = new Map();
// Each row contains 16 shades. The first row is neutral.
const paletteColors=Array.from({length:16},(_,i)=>'#'+(i*17).toString(16).padStart(2,'0').repeat(3));
for(const hue of [0,15,30,45,60,85,120,150,175,195,215,240,265,290,325]){
  for(let i=0;i<16;i++){
    const value=Math.min(1,(i+2)/9), saturation=Math.min(1,(16-i)/9);
    const channel=n=>{
      const k=(n+hue/60)%6;
      return Math.round(255*value*(1-saturation*Math.max(0,Math.min(k,4-k,1)))).toString(16).padStart(2,'0');
    };
    paletteColors.push('#'+channel(5)+channel(3)+channel(1));
  }
}
let paletteTarget;
function setLightColor(control,value){
  control.value=value;
  control.style.setProperty('--swatch',value);
  control.title=value.toUpperCase();
}
function attachPalette(control){
  control.classList.add('paletteTrigger');
  control.setAttribute('aria-haspopup','dialog');
  control.onclick=()=>{
    paletteTarget=control;
    const index=paletteColors.indexOf(control.value.toLowerCase());
    const cells=$('paletteColors').children;
    for(let i=0;i<cells.length;i++){
      cells[i].setAttribute('aria-pressed',String(i===index));
      cells[i].tabIndex=i===Math.max(0,index)?0:-1;
    }
    $('colorPalette').showModal();
    cells[Math.max(0,index)].focus();
  };
}
for(const [i,value] of paletteColors.entries()){
  const cell=document.createElement('button');
  cell.style.setProperty('--swatch',value);
  cell.title=value.toUpperCase();cell.setAttribute('aria-label',cell.title);
  cell.onclick=()=>{
    setLightColor(paletteTarget,value);
    paletteTarget.dispatchEvent(new Event('input',{bubbles:true}));
    $('colorPalette').close();
  };
  cell.onkeydown=e=>{
    const offsets={ArrowLeft:-1,ArrowRight:1,ArrowUp:-16,ArrowDown:16};
    if(!Object.hasOwn(offsets,e.key))return;
    e.preventDefault();cell.tabIndex=-1;
    const next=$('paletteColors').children[Math.max(0,Math.min(255,i+offsets[e.key]))];
    next.tabIndex=0;next.focus();
  };
  $('paletteColors').append(cell);
}
$('closePalette').onclick=()=>$('colorPalette').close();
attachPalette($('physicalColor'));
const lightInputs = {};
const effects = ['끄기','고정','흐르기','무지개','숨쉬기','그라데이션','은은한 숨쉬기'];
for(const [zone,title] of [['slot','슬롯 LED'],['ambient','바닥 조명']]) {
  const row=group('lightRow'), label=document.createElement('strong');
  const color=document.createElement('button'), effect=document.createElement('select');
  label.textContent=title; attachPalette(color);
  color.setAttribute('aria-label',title+' 색상'); effect.setAttribute('aria-label',title+' 애니메이션');
  effects.forEach((text,i)=>effect.add(new Option(text,String(i))));
  color.oninput=effect.onchange=()=>{
    if(!lightRules)return;
    const key=$('lightState').value;
    const rule=lightDrafts.get(key) || structuredClone(lightRules[key]);
    rule[zone]={color:color.value.toUpperCase(),effect:Number(effect.value)};
    lightDrafts.set(key,rule); renderPreview(); $('saveLight').disabled=savingLight;
  };
  const styles=group('effectChoices pills');
  styles.setAttribute('role','group');
  styles.setAttribute('aria-label',title+' 애니메이션');
  effect.hidden=true;
  buildPicker(effect,styles);
  effect.addEventListener('change',()=>syncPicker(effect,styles));
  lightInputs[zone]={color,effect,styles};row.append(label,color,effect,styles);$('lightZones').append(row);
}
function paintLamp(lamp,style) {
  lamp.dataset.effect=String(style?.effect ?? 0);
  lamp.style.setProperty('--lamp-color',style?.color || 'transparent');
}
function renderPreview() {
  if(!state) return;
  const sample=simulating(), key=$('lightState').value;
  const rule=sample && (lightDrafts.get(key) || lightRules?.[key]);
  const priority=['작업공간 입력 요청','작업공간 실행 중','작업공간 완료','현재 터미널','대기','상태 미확인','빈 슬롯'];
  const ambientState=liveSlots.find(s=>s.active && s.target)?.state ||
    priority.find(name=>liveSlots.some(s=>s.target && s.state===name)) || '빈 슬롯';
  paintLamp($('underglow'),sample ? rule?.ambient : lightRules?.[ambientState]?.ambient);
  for(const [id,b] of buttons) {
    const i=/^K0[1-6]$/.test(id)?Number(id.slice(1))-1:-1;
    const slot=liveSlots[i];
    b.disabled=view==='sessions' ? !slot?.target || state.busy : view==='device' && (!sample || i<0);
    if(view!=='mapping') b.setAttribute('aria-pressed',String(sample ? id===previewKey : !!slot?.active));
    const lamp=b.querySelector('.lamp');
    if(!lamp) continue;
    const live=slot?.target && (lightRules?.[slot.state]?.slot || {color:slot.lightColor,effect:slot.lightColor && slot.lightColor!=='transparent'?1:0});
    paintLamp(lamp,sample ? (id===previewKey ? rule?.slot : null) : view==='mapping' ? null : live);
  }
  $('board').classList.toggle('simulation',sample);
  $('previewCaption').hidden=view==='mapping';
  $('previewCaption').textContent=sample ? Number(previewKey.slice(1))+'번 키 · '+key+' 미리보기' : '현재 세션 조명';
}
function renderLights() {
  syncPicker($('lightState'),$('lightBar'));
  const key=$('lightState').value, rule=lightDrafts.get(key) || lightRules[key];
  for(const [zone,inputs] of Object.entries(lightInputs)){
    setLightColor(inputs.color,rule[zone].color);inputs.effect.value=rule[zone].effect;
    syncPicker(inputs.effect,inputs.styles);
  }
  $('saveLight').disabled=savingLight;
  renderPreview();
}
async function loadLights(){
  lightRules=(await api('readLighting')).rules;
  $('lightState').replaceChildren(...Object.keys(lightRules).sort().map(name=>new Option(name,name)));
  buildPicker($('lightState'),$('lightBar'));
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
let editedStyles=[], lightTarget=0;
const physicalFields=['physicalColor','physicalEffect','physicalLevel','physicalSpeed'];
function showPhysicalTarget(){
  const style=editedStyles[lightTarget]||'';
  const fallback=style||'ffffff16432';
  $('lightTargetName').textContent=lightTarget?lightTarget+'번 키 조명':'바닥 조명';
  $('overrideLight').checked=Boolean(style);
  setLightColor($('physicalColor'),'#'+fallback.slice(0,6));
  $('physicalEffect').selectedIndex=Number(fallback[6]);
  $('physicalLevel').value=parseInt(fallback.slice(7,9),16);
  $('physicalSpeed').value=parseInt(fallback.slice(9),16);
  for(const button of $('lightTargets').children)button.setAttribute('aria-pressed',String(+button.value===lightTarget));
  updatePrefsButtons();
}
for(let i=0;i<14;i++){
  const button=document.createElement('button');button.value=String(i);button.textContent=i?String(i).padStart(2,'0'):'바닥';
  button.setAttribute('aria-label',i?i+'번 키 조명':'바닥 조명');
  button.onclick=()=>{lightTarget=i;showPhysicalTarget();};$('lightTargets').append(button);
}
function capturePhysicalStyle(){
  const hex=id=>Number($(id).value).toString(16).padStart(2,'0');
  if(!$('overrideLight').checked)editedStyles[lightTarget]='';
  else if(['physicalLevel','physicalSpeed'].every(id=>$(id).value!==''&&$(id).validity.valid))
    editedStyles[lightTarget]=$('physicalColor').value.slice(1)+$('physicalEffect').selectedIndex+hex('physicalLevel')+hex('physicalSpeed');
  updatePrefsButtons();
}
for(const id of [...physicalFields,'overrideLight'])$(id).oninput=capturePhysicalStyle;
$('masterLight').oninput=()=>updatePrefsButtons();
function updatePrefsButtons(){
  const n=$('sleep').valueAsNumber;
  $('sleep').disabled=$('volume').disabled=!prefs||prefsBusy;
  const hasLights=Array.isArray(prefs?.styles);
  $('physicalLights').hidden=!hasLights;
  $('masterLight').disabled=$('overrideLight').disabled=prefsBusy;
  $('masterLightText').textContent=$('masterLight').value+'%';
  $('automaticLight').hidden=$('overrideLight').checked;
  $('physicalStyle').hidden=!$('overrideLight').checked;
  for(const id of physicalFields)$(id).disabled=prefsBusy||!$('overrideLight').checked;
  const invalidStyle=hasLights && $('overrideLight').checked && ['physicalLevel','physicalSpeed'].some(id=>$(id).value===''||!$(id).validity.valid);
  const lightChanged=hasLights && (+$('masterLight').value!==prefs.brightness || JSON.stringify(editedStyles)!==JSON.stringify(prefs.styles));
  $('readPrefs').disabled=prefsBusy;
  $('volumeText').textContent=$('volume').value+'%';
  $('savePrefs').disabled=!prefs||prefsBusy||!Number.isInteger(n)||n<0||n>120||invalidStyle||(!lightChanged && n===prefs.sleep && +$('volume').value===prefs.volume);
}
async function device(save){
  if(prefsBusy)return;prefsBusy=true;updatePrefsButtons();
  try{
    prefs=await api(save?'savePrefs':'readPrefs',save?{revision:prefs.revision,sleep:$('sleep').valueAsNumber,volume:+$('volume').value,...(prefs.styles?{brightness:+$('masterLight').value,styles:editedStyles}:{})}:{});
    editedStyles=[...(prefs.styles||[])];$('masterLight').value=prefs.brightness??100;showPhysicalTarget();
    $('sleep').value=prefs.sleep;$('volume').value=prefs.volume;$('buzzer').textContent=prefs.buzzer?'':'기기의 부저 스위치가 꺼져 있습니다.';
    if(save)announce('기기에서 저장된 값을 확인했습니다.');
  }catch(e){prefs=null;$('buzzer').textContent=e.message;}
  finally{prefsBusy=false;updatePrefsButtons();}
}
function fillProcesses(){
  const picker=$('profile');picker.replaceChildren(new Option('프로세스 선택…',''));
  const registered=document.createElement('optgroup');registered.label='등록된 앱';
  for(const p of state.profiles) registered.append(new Option(p.name,p.id));
  picker.append(registered);
  const running=document.createElement('optgroup');running.label='실행 중인 프로세스';
  for(const [id,name] of Object.entries(runningApps).sort((a,b)=>a[1].localeCompare(b[1]))) {
    if(!state.profiles.some(p=>p.id==='app.'+id))running.append(new Option(name,'running:'+id));
  }
  picker.append(running,new Option('응용 프로그램 파일 선택…','browse'));picker.value=editProfile;
}
function updateEditor(){
  categoryOverride='';$('functionSearch').value='';buildFunctions(editProfile);renderMapping();
  if(!globalEdit() && editProfile)readMenus(editProfile);
}
$('profile').onchange=async e=>{
  const value=e.target.value;
  try{
    if(value==='browse'||value.startsWith('running:')){
      const result=await api('addProfile',value==='browse'?{}:{profile:value.slice(8)});
      if(result){editProfile=result.addedProfile;renderState(result);}
    }else editProfile=value;
    fillProcesses();updateEditor();
  }catch(error){fillProcesses();fail(error);}
};
$('auto').onclick=async()=>{try{renderState(await api('toggleAuto'));}catch(err){fail(err);}};
function settingsPanel(id) {
  for (const tab of document.querySelectorAll('[data-panel]')) {
    const selected=tab.dataset.panel===id;
    tab.setAttribute('aria-pressed',String(selected));
    $(tab.dataset.panel).hidden=!selected;
  }
  renderPreview();
}
for(const tab of document.querySelectorAll('[data-panel]')) tab.onclick=()=>settingsPanel(tab.dataset.panel);
settingsPanel('hardware');
let firmwareRecords=[];
function showFirmwareRecord() {
  const record=firmwareRecords[$('firmwareRecord').selectedIndex];
  $('firmwareReport').textContent=record ? JSON.stringify(record,null,2) : '저장된 기록이 없습니다.';
  $('copyFirmwareRecord').disabled=!record;
}
async function loadFirmwareHistory() {
  try {
    firmwareRecords=await api('firmwareHistory');
    $('firmwareRecord').replaceChildren(...firmwareRecords.map(record=>{
      const first=record[0], end=record.find(e=>e.result);
      return new Option(new Date(first.time*1000).toLocaleString()+' · '+first.action+' · '+(end?.result || '진행 중 또는 미완료'));
    }));
    showFirmwareRecord();
  } catch(error) { $('firmwareReport').textContent=error.message; }
}
$('firmwareHistory').ontoggle=()=>{ if($('firmwareHistory').open) void loadFirmwareHistory(); };
$('firmwareRecord').onchange=showFirmwareRecord;
$('copyFirmwareRecord').onclick=()=>navigator.clipboard.writeText($('firmwareReport').textContent).catch(fail);
const firmwareButtons=[...document.querySelectorAll('[data-firmware]')];
for(const button of firmwareButtons)button.onclick=async()=>{
  for(const item of firmwareButtons)item.disabled=true;
  $('firmwareProgress').textContent='펌웨어 작업이 끝날 때까지 USB 연결을 유지하세요.';
  try {
    const result=await api('manageFirmware',{action:button.dataset.firmware});
    const messages={'reconnect-failed':'기기 작업은 끝났지만 앱 재연결에 실패했습니다.',diagnosed:'읽기 전용 진단을 완료했습니다.',current:'최신 키버스 펌웨어가 설치되어 있습니다.',done:'펌웨어 작업을 완료했습니다.',busy:'다른 펌웨어 작업이 진행 중입니다.',cancelled:'작업을 취소했습니다.',failed:'펌웨어 작업에 실패했습니다.'};
    $('firmwareProgress').textContent=messages[result];
    if(result==='done'){prefs=null;await device(false);await poll();}
  } catch(error){$('firmwareProgress').textContent=error.message;}
  finally{for(const item of firmwareButtons)item.disabled=false;if($('firmwareHistory').open)void loadFirmwareHistory();}
};
function show(name){
  view=name;
  document.querySelector('.profileControls').hidden=name!=='mapping';
  if(name==='device' && catalog) refreshFavoritePicker();
  for(const v of ['mapping','sessions','device']) $(v).hidden=v!==view;
  for(const b of document.querySelectorAll('[data-view]')) {
    if(b.dataset.view===view)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');
  }
  if(view==='device'&&!prefs)device(false);
  if(view!=='mapping'&&!lightRules)loadLights().catch(fail);
  if(state)renderMapping();
}
for(const b of document.querySelectorAll('[data-view]'))b.onclick=()=>show(b.dataset.view);
$('openEditor').onclick=()=>show('mapping');
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
$('manageFavorites').onclick=()=>{show('device');settingsPanel('apps');$('favoriteApp').focus();};
$('functionSearch').oninput=renderMapping;
$('reloadMenus').onclick=()=>readMenus(editProfile);
$('category').onchange=e=>{$('functionSearch').value='';categoryOverride=e.target.value;renderMapping();};
$('base').onchange=e=>{draft().base=e.target.value;renderMapping();};
$('scope').onchange=async()=>{updateEditor();if(!globalEdit()){try{runningApps=await api('runningApps');fillProcesses();}catch(error){fail(error);}}};
$('applyPreset').onclick=async()=>{
  const profile=editProfile;
  applyingPreset=true;renderMapping();
  try {
    renderState(await api('applyPreset',{profile}));
    announce('앱별 예외에 프리셋을 적용했습니다.');
  } catch(error){fail(error);}
  finally { applyingPreset=false;renderMapping(); }
};
$('inherit').onclick=async()=>{
  const key=draftKey();
  try {const next=await api('save',{profile:editProfile,input:selected,binding:'inherit'});drafts.delete(key);renderState(next);renderMapping();}
  catch(error){fail(error);}
};
$('restore').onclick=()=>{categoryOverride=''; drafts.set(draftKey(),fromBinding(defaultForKey()));renderMapping();};
$('save').onclick=async()=>{
  const input=selected, profile=editProfile, key=draftKey();
  try{const next=await api('save',{input,profile,scope:$('scope').value,binding:$('save').dataset.value});drafts.delete(key);renderState(next);announce('매핑을 저장했습니다.');}
  catch(e){fail(e);}
};
document.addEventListener('keydown',e=>{if(e.metaKey&&e.key==='s'){e.preventDefault();if(view==='mapping')$('save').click();else if(view==='device')$('savePrefs').click();}});
$('volume').oninput=$('sleep').oninput=updatePrefsButtons;
$('readPrefs').onclick=()=>device(false);$('savePrefs').onclick=()=>device(true);
$('connect').onclick=()=>api('connect').catch(fail);
for(const method of ['installClaudeHooks','removeClaudeHooks']) $(method).onclick=async()=>{try{await api(method);announce(method==='installClaudeHooks'?'Claude Code 훅을 연결했습니다. 새 세션부터 적용됩니다.':'Claude Code 훅을 해제했습니다.');}catch(error){fail(error);}};
for(const action of ['importMaps','exportMaps']) {
  $(action).onclick=async()=>{
    try {
      const result=await api(action);
      if(!result)return;
      if(action==='importMaps'){drafts.clear();renderState(result);renderMapping();}
      announce(action==='importMaps'?'키맵을 가져왔습니다.':'키맵 파일을 저장했습니다.');
    }catch(error){fail(error);}
  };
}
const firmwareWait=$('firmwareWait');
firmwareWait.addEventListener('cancel',event=>event.preventDefault());
let liveStageTimer;
async function updateLiveStage() {
  try {
    const active=(await api('firmwareHistory')).find(record=>!record.some(entry=>entry.result));
    const latest=active?.at(-1);
    if (firmwareWait.open) $('firmwareLiveStage').textContent=latest ? latest.stage+(Number.isInteger(latest.percent) ? ' · '+latest.percent+'%' : '') : '';
  } catch { /* The next poll retries while the progress dialog is open. */ }
}
window.keyberth.onFirmwareProgress(message=>{
  clearInterval(liveStageTimer);
  $('firmwareLiveStage').textContent='';
  if (message) liveStageTimer=setInterval(updateLiveStage,1000);
  if (message) {
    $('firmwareWaitTitle').textContent=message;
    if (!firmwareWait.open) firmwareWait.showModal();
  } else if (firmwareWait.open) firmwareWait.close();
});
window.keyberth.onView(show);
(async()=>{catalog=await api('catalog');build();await poll();show(view);setInterval(()=>{if(!document.hidden)poll();},900);document.addEventListener('visibilitychange',()=>{if(!document.hidden)poll();});})().catch(fail);

$('manageProfile').onchange=()=>{
  const present=state?.profiles.some(p=>p.id===$('manageProfile').value);
  $('removeProfile').disabled=!present;
};
$('addProfile').onclick=()=>{
  $('addKeymapDialog').returnValue='';
  $('addKeymapDialog').showModal();
};
$('addKeymapDialog').onclose=async()=>{
  if($('addKeymapDialog').returnValue!=='add')return;
  try{
    const result=await api('addProfile',{profile:$('addKeymapChoice').value});
    if(result){renderState(result);$('manageProfile').value=result.addedProfile;$('manageProfile').onchange();}
  }catch(error){fail(error);}
};
$('removeProfile').onclick=async()=>{
  const picker=$('manageProfile'), profile=picker.value;
  if(!state.profiles.some(p=>p.id===profile))return;
  try{
    const result=await api('removeProfile',{profile,name:picker.selectedOptions[0].textContent});
    if(result){drafts.clear();renderState(result);renderMapping();}
  }catch(error){fail(error);}
};

$('favoriteApp').onchange=()=>{
  const exists=Object.hasOwn(catalog.favorites,$('favoriteApp').value);
  $('addFavorite').disabled=exists;
  $('removeFavorite').disabled=!exists;
};
for(const method of ['addFavorite','removeFavorite']) $(method).onclick=async()=>{
  try {
    const result=await api(method,{profile:$('favoriteApp').value});
    if(!result)return;
    catalog.favorites=result;
    fillFavoritePicker();buildFunctions(editProfile);renderMapping();
  } catch(error){fail(error);}
};
