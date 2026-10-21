import {models,draw} from '/characters/sprites.js';
const hero=document.querySelector('#guild-hero'),pause=document.querySelector('#guild-motion');
const model=models.find(m=>m.id==='opus-55'),preference=matchMedia('(prefers-reduced-motion: reduce)');
let paused=false,timer=null,start=performance.now();
document.querySelectorAll('[data-family]').forEach(canvas=>draw(canvas,models.find(m=>m.family===canvas.dataset.family),{scale:1}));
function motion(){clearTimeout(timer);timer=null;pause.textContent=preference.matches?'Motion reduced':paused?'Resume motion':'Pause motion';pause.setAttribute('aria-pressed',String(paused));pause.disabled=preference.matches;
 if(paused||preference.matches||document.hidden){draw(hero,model,{scale:5});return}
 const tick=()=>{if(paused||preference.matches||document.hidden)return;draw(hero,model,{scale:5,action:'signature',frame:Math.floor((performance.now()-start)/120)%35});timer=setTimeout(tick,120)};tick();}
pause.addEventListener('click',()=>{paused=!paused;motion()});preference.addEventListener('change',motion);document.addEventListener('visibilitychange',motion);
document.querySelector('#copy-brew').addEventListener('click',async()=>{const button=document.querySelector('#copy-brew'),status=document.querySelector('#copy-status');try{await navigator.clipboard.writeText(document.querySelector('#brew-command').textContent);button.textContent='Copied';status.textContent='Homebrew command copied. Paste it into your terminal when you’re ready.'}catch{status.textContent='Select and copy the command above; clipboard access isn’t available in this browser.'}});
motion();
