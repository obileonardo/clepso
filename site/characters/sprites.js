// Original Clepso character study. Integer-grid drawings, no external image assets.
export const models = [
 {id:'opus-5',name:'Opus 5',family:'opus',version:'5',title:'The maestro',tag:'Single collar · slim baton',description:'A broad, composed owl with a score tucked into its coat. A work of art, translated into a conductor.',detail:'Classic collar, short ear tufts and a straight baton.',motion:'A small conducting gesture; the feet stay planted.'},
 {id:'opus-55',name:'Opus 5.5',family:'opus',version:'5.5',title:'The maestro · second edition',tag:'Twin collar · crested silhouette',description:'The same owl, unmistakably a new edition. The taller crest and split mantle read even without colour.',detail:'Taller paired ear tufts, wider double collar and a split mantle.',motion:'Two restrained baton beats and a slight mantle settle.'},
 {id:'fable-5',name:'Fable 5',family:'fable',version:'5',title:'The storyteller',tag:'Closed book · swept tail',description:'A fox with a travelling cloak and a little storybook. An animal storyteller connects directly to the literary form.',detail:'Open ears, a short cloak and a closed book carried at the side.',motion:'A tail curl and a quick, curious blink.'},
 {id:'fable-51',name:'Fable 5.1',family:'fable',version:'5.1',title:'The storyteller · annotated edition',tag:'Open folio · long scarf',description:'The same fox with a wider open folio and a scarf that changes its outline. Related, but visibly distinct.',detail:'Open two-page folio, long split scarf and a changed tail pose.',motion:'A page lifts, turns and settles; the tail follows a beat later.'},
 {id:'sonnet-55',name:'Sonnet 5.5',family:'sonnet',version:'5.5',title:'The verse keeper',tag:'Feathered cap · quill',description:'A compact poet with a feathered cap, quill and folded manuscript. A more direct connection than the current knight.',detail:'Flat cap, long feather, manuscript and a strong diagonal quill.',motion:'A short writing gesture, with a quiet feather response.'},
 {id:'haiku-45',name:'Haiku 4.5',family:'haiku',version:'4.5',title:'The paper crane',tag:'Folded wings · long neck',description:'A small folded-paper crane: economical, calm and immediately distinct from the rest of the party.',detail:'Long neck, angular folded wings, paper folds and two fine legs.',motion:'A tiny head tilt and one deliberate wing-fold movement.'}
];
const P={ink:'#14241d',deep:'#243e31',shade:'#40634a',green:'#60e99a',mint:'#b5efc8',cream:'#f5ebd3',paper:'#cfccae',gold:'#f4c477',amber:'#cb884a',orange:'#e6a15f'};
export function sprite(model,frame=0,action='idle') {
 const n=40,g=Array.from({length:n},()=>Array(n).fill(null));
 const dot=(x,y,c)=>{if(x>=0&&x<n&&y>=0&&y<n)g[y][x]=P[c]||c};
 const rect=(x,y,w,h,c)=>{for(let j=y;j<y+h;j++)for(let i=x;i<x+w;i++)dot(i,j,c)};
 const poly=(v,c)=>{for(let y=0;y<n;y++)for(let x=0;x<n;x++){let hit=false;for(let i=0,j=v.length-1;i<v.length;j=i++){let a=v[i],b=v[j];if(((a[1]>y+.5)!=(b[1]>y+.5))&&x+.5<(b[0]-a[0])*(y+.5-a[1])/(b[1]-a[1])+a[0])hit=!hit;}if(hit)dot(x,y,c)}};
 const line=(x,y,x1,y1,c,w=1)=>{let dx=Math.abs(x1-x),dy=-Math.abs(y1-y),sx=x<x1?1:-1,sy=y<y1?1:-1,e=dx+dy;for(;;){rect(x,y,w,w,c);if(x===x1&&y===y1)break;let e2=2*e;if(e2>=dy){e+=dy;x+=sx}if(e2<=dx){e+=dx;y+=sy}}};
 const blink=frame===30, gesture=action==='signature'&&frame>=7&&frame<=12, flutter=frame>=18&&frame<=21;
 rect(10,37,20,1,'deep');rect(13,38,14,1,'ink');
 if(model.family==='opus') {
  const newer=model.version==='5.5';
  poly([[10,20],[15,17],[27,18],[31,33],[26,35],[14,35],[8,32]],'ink');
  poly([[12,21],[18,19],[25,20],[28,33],[22,34],[13,33]],'deep');
  poly([[12,21],[15,20],[13,31],[10,32]],'green');
  poly([[24,20],[27,23],[28+(flutter?1:0),32],[24,33]],'shade');
  rect(15,32,4,4,'ink');rect(22,32,4,4,'ink');rect(14,35,6,2,'paper');rect(22,35,6,2,'paper');
  poly(newer?[[10,11],[10,3],[15,7],[23,7],[29,3],[28,14],[27,20],[14,21]]:[[10,11],[12,6],[16,8],[25,8],[28,6],[29,14],[27,20],[14,21]],'ink');
  poly(newer?[[12,10],[12,6],[16,10],[24,9],[27,6],[27,15],[25,20],[15,20]]:[[12,12],[13,9],[17,10],[25,10],[27,9],[27,16],[25,20],[15,19]],'shade');
  poly([[13,12],[18,11],[20,13],[21,11],[26,12],[26,17],[23,20],[19,18],[16,20],[13,17]],'cream');
  rect(15,14,3,blink?1:3,'ink');rect(22,14,3,blink?1:3,'ink');if(!blink){dot(16,14,'mint');dot(23,14,'mint')}
  poly([[18,17],[22,17],[20,20]],'gold');
  poly([[12,20],[19,23],[17,27],[11,23]],newer?'green':'paper');
  poly([[27,20],[20,23],[23,27],[29,23]],newer?'mint':'shade');
  if(newer){line(13,22,17,25,'cream');line(26,22,23,25,'cream');poly([[18,29],[22,29],[22,35],[20,33],[18,35]],'mint');}
  rect(18,23,3,7,'ink');rect(19,24,1,5,'gold');
  rect(13,27,5,5,'ink');rect(13,27,4,4,'paper');line(14,28,15,28,'shade');
  const by=gesture?17:22;
  line(26,23,32,by,'ink',3);line(27,23,32,by,'green',2);rect(32,by,2,3,'gold');
  line(33,by,gesture?36:34,gesture?9:12,'ink',2);line(33,by,gesture?36:34,gesture?9:12,'cream');
  if(newer){dot(34,11,'gold');dot(35,10,'gold');}
 }
 if(model.family==='fable') {
  const newer=model.version==='5.1',tail=flutter?1:0;
  poly(newer?[[12,27],[9,19+tail],[5,18+tail],[3,22],[4,29],[9,33],[16,33],[18,29]]:[[12,26],[8,20+tail],[4,23+tail],[3,29],[6,33],[15,34],[18,30]],'ink');
  poly(newer?[[11,27],[8,21+tail],[5,20+tail],[5,25],[7,29],[13,31]]:[[11,27],[8,23+tail],[5,24+tail],[5,29],[8,31],[14,32]],'amber');
  poly(newer?[[5,20+tail],[7,21+tail],[8,24],[6,26],[5,24]]:[[8,23+tail],[5,24+tail],[5,28],[8,29],[10,27]],'cream');
  poly([[14,20],[25,20],[28,32],[22,35],[13,33],[12,25]],'ink');
  poly([[15,21],[24,21],[25,31],[20,33],[14,31]],'green');
  poly([[15,22],[18,22],[17,32],[13,31]],'shade');
  rect(15,32,4,4,'ink');rect(23,32,4,4,'ink');rect(14,35,6,2,'amber');rect(23,35,6,2,'amber');
  poly([[11,13],[10,4],[17,8],[23,8],[30,4],[29,16],[25,22],[17,22]],'ink');
  poly([[13,13],[12,7],[17,11],[23,11],[28,7],[27,16],[24,20],[17,20]],'orange');
  poly([[13,9],[16,12],[13,13]],'amber');poly([[27,9],[24,12],[27,13]],'amber');
  poly([[12,15],[18,17],[20,19],[23,17],[28,15],[25,21],[20,23],[15,21]],'cream');
  rect(15,14,2,blink?1:2,'ink');rect(24,14,2,blink?1:2,'ink');rect(19,18,3,2,'ink');dot(20,20,'amber');
  rect(13,21,14,3,'deep');rect(16,22,9,2,'mint');
  if(newer){poly([[13,23],[15,24],[13,35],[10,33],[11,27]],'mint');poly([[15,24],[17,24],[16,34],[14,32]],'green');}
  if(newer){
   poly([[22,25],[28,23],[34,25],[34,32],[28,30],[22,32]],'ink');
   poly([[23,26],[27,25],[27,29],[23,30]],'cream');poly([[29,25],[33,26],[33,30],[29,29]],'paper');line(28,25,28,30,'amber');
   if(gesture){poly([[28,25],[31,21],[32,24],[29,29]],'cream');line(30,24,30,27,'paper');}
   rect(21,28,2,2,'orange');rect(33,28,2,2,'orange');
  }else{rect(25,24,7,9,'ink');rect(26,24,5,7,'amber');rect(27,25,3,1,'gold');rect(26,31,5,1,'paper');rect(24,27,3,2,'orange');}
 }
 if(model.family==='sonnet') {
  poly([[12,21],[25,21],[28,32],[24,35],[12,35],[9,31]],'ink');
  poly([[14,22],[23,22],[25,32],[13,33]],'shade');poly([[13,23],[17,24],[15,32],[11,31]],'green');
  rect(14,33,4,4,'ink');rect(22,33,4,4,'ink');rect(12,35,7,2,'paper');rect(22,35,6,2,'paper');
  rect(13,12,13,10,'ink');poly([[15,13],[24,13],[25,19],[22,22],[17,21],[15,18]],'cream');rect(16,16,2,blink?1:2,'ink');rect(22,16,2,blink?1:2,'ink');dot(20,19,'amber');
  poly([[10,12],[13,7],[22,7],[27,10],[29,13],[12,14]],'ink');poly([[13,11],[15,9],[22,9],[25,11]],'green');rect(11,12,16,2,'deep');rect(17,11,4,1,'mint');
  poly([[23,10],[26,3],[31,2],[29,7],[25,11]],'ink');poly([[25,9],[27,4],[29,4],[27,8]],'paper');
  rect(13,22,13,3,'mint');poly([[23,24],[26,24],[28+(flutter?1:0),31],[25,30]],'green');
  rect(12,26,8,7,'ink');rect(13,26,6,6,'paper');rect(14,27,4,1,'shade');rect(14,29,3,1,'shade');
  const q=gesture?-1:0;line(26,30,33,17+q,'ink',2);line(26,30,33,17+q,'gold');poly([[29,23],[30,17+q],[35,14+q],[34,19+q]],'cream');line(29,23,33,17+q,'amber');rect(25,27,3,2,'cream');
 }
 if(model.family==='haiku') {
  const tilt=gesture?1:0;
  line(17,29,16,36,'ink',2);line(23,29,24,36,'ink',2);line(17,30,17,35,'gold');line(23,30,24,35,'gold');rect(13,36,5,1,'gold');rect(24,36,5,1,'gold');
  poly([[7,17],[17,23],[24,20],[28,23],[25,30],[17,32],[9,26],[5,24]],'ink');
  poly([[8,20],[17,25],[24,22],[26,24],[23,29],[17,30],[10,25]],'paper');
  poly([[13,23],[8,11+(flutter?1:0)],[18,17],[22,25]],'ink');poly([[14,23],[10,14+(flutter?1:0)],[17,19],[20,25]],'cream');
  poly([[18,26],[21,18],[27,16],[24,27]],'ink');poly([[20,25],[23,20],[25,19],[23,26]],'mint');
  poly([[25,25],[23,20],[24,13],[27,8+tilt],[31,8+tilt],[33,11+tilt],[31,15],[28,15],[27,20],[29,23]],'ink');
  poly([[25,23],[25,19],[26,14],[28,10+tilt],[31,10+tilt],[31,13],[27,14],[27,20],[28,23]],'cream');
  rect(28,11+tilt,2,blink?1:2,'ink');poly([[31,12+tilt],[37,14+tilt],[31,15+tilt]],'gold');
  line(11,24,17,28,'shade');line(18,29,23,27,'shade');
 }
 return g;
}
export function draw(canvas,model,{frame=0,action='idle',scale=4,monochrome=false}={}){
 const grid=sprite(model,frame,action),ctx=canvas.getContext('2d');canvas.width=40*scale;canvas.height=40*scale;
 ctx.imageSmoothingEnabled=false;
 for(let y=0;y<40;y++)for(let x=0;x<40;x++)if(grid[y][x]){let c=grid[y][x];if(monochrome){const rgb=c.match(/[\da-f]{2}/gi).map(v=>parseInt(v,16));const l=Math.round(rgb[0]*.2126+rgb[1]*.7152+rgb[2]*.0722);c=`rgb(${l},${l},${l})`;}ctx.fillStyle=c;ctx.fillRect(x*scale,y*scale,scale,scale);}
}
