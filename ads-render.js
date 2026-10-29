/* Public delivery uses validated settings only. Pasted admin scripts stay private. */
window.publicAdUnits=new Map();
window.loadPublicAds=async()=>{try{const rows=await PublicationDB.request('/rest/v1/cms_ad_units?select=placement,provider,image_url,target_url,ad_unit_path,label');window.publicAdUnits=new Map(rows.map(a=>[a.placement,a]))}catch(e){window.publicAdUnits=new Map();console.warn('Ad settings could not be loaded:',e.message)}};
(()=>{
 const PATH=/^\/\d+\/[A-Za-z0-9_./%-]+$/;
 let sequence=0,loading=false,libraryState='idle',queued=false,servicesReady=false;
 const records=new Map();
 const mode=typeof window.__tcfapi==='function'?'cmp':'limited';
 const escape=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
 const https=u=>{try{const url=new URL(window.resolveMediaURL?window.resolveMediaURL(u):u);return url.protocol==='https:'&&!url.username&&!url.password?url.href:null}catch{return null}};
 function state(record,value){record.state=value;record.element.dataset.adState=value}
 function request(record){if(record.requested||!record.element.isConnected||!record.nearViewport||document.hidden)return;record.requested=true;state(record,'requesting');try{window.googletag.pubads().refresh([record.slot])}catch(e){state(record,'error');console.warn('Ad request failed:',e.message)}}
 const visible=typeof IntersectionObserver==='function'?new IntersectionObserver(entries=>{for(const entry of entries){const record=records.get(entry.target.id);if(!record)continue;record.nearViewport=entry.isIntersecting;if(record.nearViewport)window.googletag.cmd.push(()=>request(record))}},{rootMargin:'600px 0px',threshold:0}):null;
 function configure(){
  if(servicesReady)return;
  const g=window.googletag,pubads=g.pubads();
  g.setConfig({disableInitialLoad:true});
  if(mode==='limited')pubads.setPrivacySettings({limitedAds:true});
  for(const [event,next] of [['slotRequested','requested'],['slotResponseReceived','response'],['impressionViewable','viewable']])pubads.addEventListener(event,e=>{const record=records.get(e.slot.getSlotElementId());if(record)state(record,next)});
  pubads.addEventListener('slotRenderEnded',e=>{const record=records.get(e.slot.getSlotElementId());if(!record)return;state(record,e.isEmpty?'no-fill':'rendered');record.element.closest('.ad-wrap').hidden=!!e.isEmpty});
  g.enableServices();servicesReady=true;libraryState='ready';
 }
 function ensureLibrary(){
  if(loading)return;loading=true;libraryState='loading';
  window.googletag=window.googletag||{cmd:[]};
  window.googletag.cmd.push(configure);
  const script=document.createElement('script');script.id='anjupankaj-gpt-library';script.async=true;script.crossOrigin='anonymous';
  script.src=mode==='cmp'?'https://securepubads.g.doubleclick.net/tag/js/gpt.js':'https://pagead2.googlesyndication.com/tag/js/gpt.js';
  script.onerror=()=>{libraryState='blocked-or-unavailable';document.querySelectorAll('[data-gpt-path]').forEach(el=>el.dataset.adState='script-unavailable');console.warn('Google Publisher Tag could not load. Check the network, content policy, or ad blocker.')};
  document.head.appendChild(script);
 }
 function scan(){
  const elements=[...document.querySelectorAll('[data-gpt-path]')];
  if(!elements.length&&!loading)return;
  ensureLibrary();
  window.googletag.cmd.push(()=>{
   for(const [id,record] of records){if(!record.element.isConnected){visible?.unobserve(record.element);window.googletag.destroySlots([record.slot]);records.delete(id)}}
   for(const element of elements){
    if(!element.isConnected||records.has(element.id)||element.closest('[hidden]')||!PATH.test(element.dataset.gptPath))continue;
    const slot=window.googletag.defineSlot(element.dataset.gptPath,[300,250],element.id);
    if(!slot){element.dataset.adState='invalid-slot';continue}
    slot.addService(window.googletag.pubads());
    slot.setConfig({targeting:{anjupankaj_placement:element.dataset.placement}});
    const record={element,slot,placement:element.dataset.placement,path:element.dataset.gptPath,requested:false,nearViewport:!visible,state:'registered'};
    records.set(element.id,record);state(record,'registered');window.googletag.display(element.id);
    if(visible)visible.observe(element);else request(record);
   }
  });
 }
 function schedule(){if(queued)return;queued=true;queueMicrotask(()=>{queued=false;scan()})}
 window.renderAdMarkup=placement=>{
  const a=window.publicAdUnits.get(placement);if(!a)return '';let creative;
  if(a.provider==='direct'){const image=https(a.image_url),url=https(a.target_url);if(!image||!url)return '';creative='<a class="direct-banner" href="'+escape(url)+'" target="_blank" rel="sponsored noopener noreferrer"><img src="'+escape(image)+'" width="300" height="250" loading="lazy" alt="'+escape(a.label||'Advertisement')+'"></a>'}
  else if(a.provider==='google_ad_manager'){
   if(!PATH.test(a.ad_unit_path||''))return '';
   const id='anjupankaj-gpt-'+String(placement).replace(/[^a-z0-9_-]/gi,'')+'-'+(++sequence);
   creative='<div class="gpt-slot" id="'+id+'" data-gpt-path="'+escape(a.ad_unit_path)+'" data-placement="'+escape(placement)+'" data-ad-state="pending" style="width:300px;height:250px" aria-label="Advertisement"></div>';
  }else creative='<div class="ad rail-ad"><div class="eyebrow">ANJU PANKAJ</div><strong>A fresh<br>perspective.</strong><em>Your brand here ↗</em><span class="size">300 × 250 · sample</span></div>';
  return '<aside class="feed-ad ad-wrap"><span class="ad-label">'+escape(a.label||'Advertisement')+(a.provider==='sample'?' · sample':'')+'</span>'+creative+'</aside>';
 };
 window.SocialAds={mount:scan,diagnostics:()=>({library:libraryState,privacyMode:mode,slots:[...records.values()].map(r=>({id:r.element.id,placement:r.placement,path:r.path,size:[300,250],state:r.state,requested:r.requested}))})};
 new MutationObserver(schedule).observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['hidden']});
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)for(const record of records.values())window.googletag.cmd.push(()=>request(record))});
 schedule();
})();
