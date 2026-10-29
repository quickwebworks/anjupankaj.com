const assert=require('node:assert/strict'),fs=require('fs'),vm=require('vm');
function harness(cmp=false){
 const nodes=[],scripts=[],definitions=[],requests=[],destroyed=[],events={},visibility=[];let services=0,privacy;
 const document={hidden:false,body:{},head:{appendChild:s=>scripts.push(s)},createElement:()=>({}),querySelectorAll:()=>nodes,addEventListener:(name,fn)=>{if(name==='visibilitychange')visibility.push(fn)}};
 const pubads={setPrivacySettings:p=>privacy=p,addEventListener:(name,fn)=>events[name]=fn,refresh:slots=>requests.push(...slots)};
 const googletag={cmd:{push:fn=>fn()},pubads:()=>pubads,setConfig:c=>assert.equal(c.disableInitialLoad,true),enableServices:()=>services++,defineSlot:(path,size,id)=>{assert.deepEqual(Array.from(size),[300,250]);const s={path,id,getSlotElementId:()=>id,addService(){return s},setConfig(config){assert.ok(config.targeting.anjupankaj_placement);return s}};definitions.push(s);return s},display:id=>assert.ok(nodes.some(n=>n.id===id)),destroySlots:s=>destroyed.push(...s)};
 const context={window:{googletag,...(cmp?{__tcfapi(){}}:{})},document,PublicationDB:{request:async()=>[]},Map,URL,console,queueMicrotask:fn=>fn(),MutationObserver:class{constructor(fn){this.fn=fn}observe(){}},IntersectionObserver:undefined};
 vm.createContext(context);vm.runInContext(fs.readFileSync(require('path').join(__dirname,'../ads-render.js'),'utf8'),context);
 function add(placement='feed'){context.window.publicAdUnits.set(placement,{provider:'google_ad_manager',ad_unit_path:'/22932458576/PIS2026SOCIAL'});const html=context.window.renderAdMarkup(placement);const id=html.match(/id="([^"]+)"/)[1],wrapper={hidden:false};const el={id,dataset:{gptPath:'/22932458576/PIS2026SOCIAL',placement},isConnected:true,closest:s=>s==='[hidden]'?null:wrapper};nodes.push(el);return el}
 return {context,nodes,scripts,definitions,requests,destroyed,events,visibility,add,get services(){return services},get privacy(){return privacy}};
}
const h=harness(),a=h.add(),b=h.add();assert.notEqual(a.id,b.id);h.context.window.SocialAds.mount();assert.equal(h.services,1);assert.equal(h.scripts.length,1);assert.match(h.scripts[0].src,/pagead2\.googlesyndication\.com/);assert.equal(h.privacy.limitedAds,true);assert.equal(h.requests.length,2);h.context.window.SocialAds.mount();assert.equal(h.requests.length,2);assert.equal(h.definitions.length,2);
h.events.slotRenderEnded({slot:h.definitions[0],isEmpty:true});assert.equal(a.closest('.ad-wrap').hidden,true);assert.equal(a.dataset.adState,'no-fill');
a.isConnected=false;h.context.window.SocialAds.mount();assert.equal(h.destroyed.length,1);assert.equal(h.context.window.SocialAds.diagnostics().slots.length,1);
h.context.document.hidden=true;const c=h.add('article_inline');h.context.window.SocialAds.mount();assert.equal(h.requests.length,2);h.context.document.hidden=false;h.visibility[0]();assert.equal(h.requests.length,3);h.visibility[0]();assert.equal(h.requests.length,3);
h.context.window.publicAdUnits.set('bad',{provider:'google_ad_manager',ad_unit_path:'javascript:alert(1)'});assert.equal(h.context.window.renderAdMarkup('bad'),'');
const standard=harness(true);standard.add();standard.context.window.SocialAds.mount();assert.match(standard.scripts[0].src,/securepubads\.g\.doubleclick\.net/);assert.equal(standard.privacy,undefined);
console.log('PASS: unique 300x250 slots, one loader, requests once, removal cleanup, hidden-tab deferral, no-fill handling, CMP/limited modes and invalid-path rejection');
