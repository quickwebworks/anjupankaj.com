/* Parse common WordPress mysqldump data. Never execute SQL or imported HTML. */
function statementStream(consume) {
 let carry='',parts=[],bytes=0,quote=null,escape=false,line=false,block=false;
 function feed(chunk,final=false){
  const sql=carry+chunk,limit=final?sql.length:Math.max(0,sql.length-3);let start=0,i=0;
  for(;i<limit;i++){
   const c=sql[i],n=sql[i+1];
   if(line){if(c==='\n')line=false;continue}
   if(block){if(c==='*'&&n==='/'){block=false;i++}continue}
   if(quote){if(escape){escape=false;continue}if(c==='\\'){escape=true;continue}if(c===quote){if(n===quote){i++;continue}quote=null}continue}
   if(c==="'"||c==='"'||c==='`'){quote=c;continue}
   if((c==='-'&&n==='-'&&/\s/.test(sql[i+2]||' '))||c==='#'){line=true;continue}
   if(c==='/'&&n==='*'){block=true;i++;continue}
   if(c===';'){
    parts.push(sql.slice(start,i));consume(parts.join(''));parts=[];bytes=0;start=i+1;
   }
  }
  const end=Math.min(i,sql.length),tail=sql.slice(start,end);parts.push(tail);bytes+=tail.length;
  if(bytes>32*1024*1024)throw Error('A single SQL statement exceeds 32 MB. Re-export with smaller INSERT batches, or use the production server importer.');
  carry=sql.slice(end);
  if(final){if(quote||block)throw Error('The SQL file ends inside a quoted value or comment.');const rest=parts.join('');if(rest.trim())consume(rest);parts=[]}
 }
 return {feed};
}
function statements(sql,consume){statementStream(consume).feed(sql,true)}
function values(s){
 let rows=[],row=null,token='',quoted=false,inQuote=false,escape=false,wasQuoted=false;
 const push=()=>{row.push(wasQuoted?token:(/^null$/i.test(token.trim())?null:token.trim()));token='';wasQuoted=false};
 for(let i=0;i<s.length;i++){
  let c=s[i];
  if(inQuote){if(escape){const map={'0':'\0','n':'\n','r':'\r','t':'\t','b':'\b','Z':'\x1a'};token+=map[c]??c;escape=false;continue}if(c==='\\'){escape=true;continue}if(c==="'"){if(s[i+1]==="'"){token+="'";i++}else inQuote=false;continue}token+=c;continue}
  if(c==="'"){if(!token.trim())token="";inQuote=true;wasQuoted=true;continue}
  if(c==='('){if(row)throw Error('Unsupported SQL value expression. Use plain INSERT VALUES exports.');row=[];token='';continue}
  if(c===')'){if(!row)throw Error('Invalid INSERT data.');push();rows.push(row);row=null;continue}
  if(c===','){if(row)push();continue}
  if(row){if(wasQuoted&&/\s/.test(c))continue;token+=c}
  else if(!/\s/.test(c))throw Error('Unsupported INSERT syntax. Use an unmodified mysqldump VALUES export.');
 }
 if(inQuote||row)throw Error('Incomplete INSERT statement.');return rows;
}
function clean(s){return s.replace(/^\s*(?:(?:--[^\n]*\n)|(?:#[^\n]*\n)|(?:\/\*[\s\S]*?\*\/)|\s)*/,'').trim()}
function collector(opts){
 const schema={},tables={},warnings=[];
 const suffix=/^(.*?)(posts|postmeta|terms|term_taxonomy|term_relationships)$/;
 function consume(raw){
  const s=clean(raw);let m=s.match(/^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?`?([\w]+)`?\s*\(/i);
  if(m&&suffix.test(m[1])){schema[m[1]]=[...s.matchAll(/^\s*`([^`]+)`\s+\w+/gm)].map(x=>x[1]);return}
  m=s.match(/^INSERT\s+(?:IGNORE\s+)?INTO\s+`?([\w]+)`?\s*(?:\(([^)]*)\))?\s+VALUES\s*([\s\S]*)$/i);
  if(!m){if(/^INSERT\s/i.test(s))warnings.push('An unsupported INSERT statement was skipped.');return}
  const name=m[1];if(!suffix.test(name))return;
  const cols=m[2]?m[2].split(',').map(x=>x.trim().replace(/^`|`$/g,'')):schema[name];
  if(!cols?.length)throw Error('No column definition for '+name+'. Export CREATE TABLE statements or INSERT column lists.');
  schema[name]=cols;
  const parsed=values(m[3]);if(!tables[name])tables[name]=[];
  for(const row of parsed){if(row.length!==cols.length)throw Error('Column count mismatch in '+name+'.');const rec={};cols.forEach((c,i)=>rec[c]=row[i]);if(name.endsWith('postmeta')&&!['_thumbnail_id','_wp_attached_file'].includes(rec.meta_key))continue;
   if(name.endsWith('posts')){
    if(!['post','attachment'].includes(rec.post_type))continue;
    if(rec.post_type==='post'&&(rec.post_status==='trash'||(opts.publishedOnly&&rec.post_status!=='publish')||(opts.from&&String(rec.post_date).slice(0,10)<opts.from)||(opts.to&&String(rec.post_date).slice(0,10)>opts.to)))continue;
   }
   tables[name].push(rec)}
 }
 function finish(){
 const prefixes=Object.keys(tables).filter(x=>/posts$/.test(x)&&(schema[x]||[]).includes('post_type')).map(x=>x.slice(0,-5));
 let prefix=opts.prefix||prefixes[0];
 if(!opts.prefix&&prefixes.length>1)throw Error('Multiple WordPress sites detected. Enter the intended table prefix: '+prefixes.join(', '));
 if(prefix===undefined||!tables[prefix+'posts'])throw Error('No WordPress posts table found. Include posts and postmeta in the export.');
 const all=tables[prefix+'posts'],meta=tables[prefix+'postmeta']||[],byId=new Map(all.map(p=>[String(p.ID),p]));
 const attached=new Map(),thumbs=new Map();for(const m of meta){if(m.meta_key==='_wp_attached_file')attached.set(String(m.post_id),m.meta_value);if(m.meta_key==='_thumbnail_id')thumbs.set(String(m.post_id),String(m.meta_value))}
 const terms=new Map((tables[prefix+'terms']||[]).map(t=>[String(t.term_id),t]));
 const taxonomy=new Map((tables[prefix+'term_taxonomy']||[]).map(t=>[String(t.term_taxonomy_id),t]));const relations=new Map();
 for(const r of tables[prefix+'term_relationships']||[]){const id=String(r.object_id);if(!relations.has(id))relations.set(id,[]);const tax=taxonomy.get(String(r.term_taxonomy_id));const term=tax&&terms.get(String(tax.term_id));if(term&&['category','post_tag'].includes(tax.taxonomy))relations.get(id).push({type:tax.taxonomy,name:term.name,slug:term.slug})}
 const safeUrl=value=>{try{const u=new URL(value);return ['https:','http:'].includes(u.protocol)?u.href:null}catch{return null}};
 function mediaUrl(p){const path=attached.get(String(p.ID));if(path){if(/^https?:\/\//i.test(path))return safeUrl(path);if(path.startsWith('/'))return safeUrl(opts.source.replace(/\/$/,'')+path);return safeUrl(opts.source.replace(/\/$/,'')+'/wp-content/uploads/'+path)}return safeUrl(p.guid)}
 const posts=all.filter(p=>p.post_type==='post'&&p.post_status!=='trash'&&(!opts.publishedOnly||p.post_status==='publish')&&(!opts.from||String(p.post_date).slice(0,10)>=opts.from)&&(!opts.to||String(p.post_date).slice(0,10)<=opts.to)).map(p=>{const tid=thumbs.get(String(p.ID)),attachment=tid&&byId.get(tid);return {source_id:String(p.ID),source_author_id:String(p.post_author),slug:p.post_name,title:p.post_title,excerpt:p.post_excerpt,content_html:p.post_content,status:p.post_status,published_at_source:p.post_date,published_at_gmt:p.post_date_gmt,modified_at_source:p.post_modified,source_guid:p.guid,featured_attachment_id:tid||null,featured_image_url:attachment?mediaUrl(attachment):null,taxonomy:relations.get(String(p.ID))||[]}});
 const used=new Set(posts.map(p=>p.featured_attachment_id).filter(Boolean));const postIds=new Set(posts.map(p=>p.source_id));
 const media=all.filter(p=>p.post_type==='attachment'&&(used.has(String(p.ID))||postIds.has(String(p.post_parent))||posts.some(post=>p.guid&&post.content_html.includes(p.guid)))).map(p=>({source_id:String(p.ID),parent_id:String(p.post_parent),title:p.post_title,mime_type:p.post_mime_type,source_url:mediaUrl(p),attached_file:attached.get(String(p.ID))||null}));
 if(!tables[prefix+'postmeta'])warnings.push('postmeta is missing: featured-image and original upload-path mapping may be incomplete.');
 if(!tables[prefix+'terms'])warnings.push('Taxonomy tables are missing: categories/tags may be incomplete.');
 if(!posts.length)warnings.push('No posts match the selected dates and status. Confirm the source publication dates.');
 const missing=posts.filter(p=>p.featured_attachment_id&&!p.featured_image_url).length;if(missing)warnings.push(missing+' featured image references could not be resolved.');
 warnings.push('Media URLs are preserved but their HTTP availability has not been checked.');
 warnings.push('Imported HTML remains untrusted. Sanitize and convert it before rendering in the production CMS.');
 return {schema_version:1,source_url:opts.source,table_prefix:prefix,date_filter:{from:opts.from,to_inclusive:opts.to},media_mode:'preserve_original_urls',generated_at:new Date().toISOString(),posts,media,warnings:[...new Set(warnings)],source_counts:{posts_table:all.length,attachments:all.filter(p=>p.post_type==='attachment').length}};
}
 return {consume,finish};
}
function parse(sql,opts){const c=collector(opts);statements(sql,c.consume);return c.finish()}
async function parseFile(file,opts,onProgress=()=>{}){
 if(!file||file.size>400*1024*1024)throw Error('Choose an SQL file up to 400 MB.');
 const c=collector(opts),scanner=statementStream(c.consume),decoder=new TextDecoder('utf-8',{fatal:true});
 const chunkSize=1024*1024;
 for(let offset=0;offset<file.size;offset+=chunkSize){
  const data=await file.slice(offset,offset+chunkSize).arrayBuffer();
  scanner.feed(decoder.decode(data,{stream:true}));
  onProgress(Math.min(offset+chunkSize,file.size),file.size);
 }
 scanner.feed(decoder.decode(),true);return c.finish();
}
if(typeof self!=='undefined')self.onmessage=async e=>{
 try{const result=e.data.file?await parseFile(e.data.file,e.data.options,(read,total)=>self.postMessage({progress:true,read,total})):parse(e.data.sql,e.data.options);self.postMessage({ok:true,result})}
 catch(err){self.postMessage({ok:false,error:err.message})}
};
if(typeof module!=='undefined')module.exports={parse,values,parseFile,statementStream};
