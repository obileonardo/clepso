import {models,draw,sprite} from './sprites.js';
const $=id=>document.getElementById(id),system=matchMedia('(prefers-reduced-motion: reduce)');
let selected=models.find(m=>m.id===location.hash.slice(1))||models[3],paused=false,reduced=system.matches,monochrome=false,action='signature',timer=null,epoch=performance.now(),lastFrame=-1;
const old=await fetch('./assets/current-sprites.json').then(r=>{if(!r.ok)throw Error('Current sprite references unavailable');return r.json()});
const mini=$('miniatures');
for(const model of models){
 const button=document.createElement('button');button.className='model-card';button.dataset.model=model.id;button.setAttribute('aria-pressed','false');
 const art=document.createElement('span');art.className='art';const canvas=document.createElement('canvas');canvas.setAttribute('aria-hidden','true');canvas.dataset.staticModel=model.id;art.append(canvas);
 const name=document.createElement('span');name.className='name';name.textContent=model.name;const tag=document.createElement('span');tag.className='tag';tag.textContent=model.tag;
 button.append(art,name,tag);button.addEventListener('click',()=>select(model));$('roster').append(button);
 const item=document.createElement('div');item.className='mini';const small=document.createElement('canvas');small.setAttribute('aria-hidden','true');small.dataset.miniModel=model.id;const label=document.createElement('span');label.textContent=model.name;item.append(small,label);mini.append(item);
}
function stills(){
 document.querySelectorAll('[data-static-model]').forEach(c=>draw(c,models.find(m=>m.id===c.dataset.staticModel),{scale:3,monochrome}));
 document.querySelectorAll('[data-mini-model]').forEach(c=>draw(c,models.find(m=>m.id===c.dataset.miniModel),{scale:1,monochrome}));
 draw($('new-large'),selected,{scale:4,monochrome});
 const c=$('old-large'),ctx=c.getContext('2d');ctx.clearRect(0,0,c.width,c.height);const colors={a:'#60e99a',b:'#f5ebd3',c:'#40634a',d:'#101410'};
 old[selected.family].forEach((row,y)=>[...row].forEach((ch,x)=>{if(colors[ch]){ctx.fillStyle=monochrome?(ch==='a'?'#bbbbbb':ch==='b'?'#ededed':ch==='c'?'#555555':'#101410'):colors[ch];ctx.fillRect(20+x*10,20+y*10,10,10)}}));
}
function select(model){
 selected=model;history.replaceState(null,'','#'+model.id);epoch=performance.now();lastFrame=-1;
 $('family-label').textContent=model.family.toUpperCase()+' / EDITION '+model.version;$('character-title').textContent=model.title;$('description').textContent=model.description;$('detail').textContent=model.detail;$('motion-copy').textContent=model.motion;$('stage-model').textContent=model.name.toUpperCase();$('hero').setAttribute('aria-label',model.name+' — '+model.title);
 document.querySelectorAll('[data-model]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.model===model.id)));
 $('announcement').textContent=model.name+' selected. '+model.detail;
 stills();schedule();
}
function syncControls(){
 $('pause').textContent=paused?'Resume':'Pause';$('pause').setAttribute('aria-pressed',String(paused));$('pause').disabled=reduced;
 $('reduce').checked=reduced;$('reduce').disabled=system.matches;
 $('milestone').disabled=reduced||paused;
 $('motion-state').textContent=reduced?'REDUCE MOTION':paused?'PAUSED':'MOTION ON';
 $('idle').setAttribute('aria-pressed',String(action==='idle'));$('signature').setAttribute('aria-pressed',String(action==='signature'));
}
function schedule(){
 clearTimeout(timer);timer=null;syncControls();
 const stopped=paused||reduced||document.hidden;
 if(stopped){draw($('hero'),selected,{scale:6,monochrome});return}
 const tick=()=>{if(paused||reduced||document.hidden)return;const frame=Math.floor((performance.now()-epoch)/120)%35;if(frame!==lastFrame){draw($('hero'),selected,{frame,action,scale:6,monochrome});lastFrame=frame}timer=setTimeout(tick,120)};
 tick();
}
$('pause').addEventListener('click',()=>{paused=!paused;lastFrame=-1;schedule()});
$('reduce').addEventListener('change',event=>{reduced=event.target.checked;schedule()});
system.addEventListener('change',event=>{reduced=event.matches;lastFrame=-1;schedule()});
document.addEventListener('visibilitychange',()=>{lastFrame=-1;schedule()});
$('mono').addEventListener('change',event=>{monochrome=event.target.checked;lastFrame=-1;stills();schedule()});
for(const mode of ['idle','signature'])$(mode).addEventListener('click',()=>{action=mode;epoch=performance.now();lastFrame=-1;schedule()});
$('surface').addEventListener('click',()=>{const enabled=$('stage').classList.toggle('paper');$('surface').setAttribute('aria-pressed',String(enabled));$('surface').textContent=enabled?'Dark background':'Paper background'});
let milestoneTimer;
$('milestone').addEventListener('click',()=>{clearTimeout(milestoneTimer);$('stage').classList.remove('celebrating');void $('stage').offsetWidth;$('stage').classList.add('celebrating');$('announcement').textContent='Level-up animation preview only. No usage or level data changed.';milestoneTimer=setTimeout(()=>$('stage').classList.remove('celebrating'),750)});
// Expose only non-sensitive design diagnostics for local visual checks.
window.studyState=()=>({selected:selected.id,paused,reduced,monochrome,action,timerActive:timer!==null&&!paused&&!reduced&&!document.hidden,gridSize:sprite(selected).length,models:models.length});
select(selected);
