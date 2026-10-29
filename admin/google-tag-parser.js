/* Google Publisher Tag settings extractor. Pasted JavaScript is never evaluated. */
function parseGoogleTags(header,body){
 if(!header.trim()||!body.trim())throw Error('Paste both Document header and Document body code.');
 if(header.length>100000||body.length>100000)throw Error('Each tag block must be under 100 KB.');
 if(/adsbygoogle|pagead2\.googlesyndication/i.test(header+body))throw Error('This is AdSense code. Choose Google Publisher Tag in Google Ad Manager.');
 const definitions=[...header.matchAll(/(?:googletag\s*\.\s*)?defineSlot\s*\(\s*(['"])(\/\d+\/[^'"\r\n]+)\1\s*,\s*(\[[\s\S]*?\])\s*,\s*(['"])([^'"]+)\4\s*\)/g)];
 if(definitions.length!==1)throw Error('Paste the header for one ad unit with a defineSlot(...) call. Multiple slots in one block are not supported.');
 const m=definitions[0];let sizes;try{sizes=JSON.parse(m[3])}catch{throw Error('The slot size must be a literal [300, 250] array.');}
 const pairs=typeof sizes[0]==='number'?[sizes]:sizes;
 if(!pairs.length||pairs.some(p=>!Array.isArray(p)||p.length!==2||p[0]!==300||p[1]!==250))throw Error('Only 300 × 250 is supported. Generate a tag with that size only.');
 const slot=m[5];if(!/^[a-zA-Z0-9_-]{1,160}$/.test(slot))throw Error('The generated slot ID contains unsupported characters.');
 const div=[...body.matchAll(/<div\b[^>]*\bid\s*=\s*(['"])([^'"]+)\1/gi)].map(m=>m[2]);
 const calls=[...body.matchAll(/(?:googletag\s*\.\s*)?display\s*\(\s*(['"])([^'"]+)\1\s*\)/g)].map(m=>m[2]);
 if(div.length!==1||calls.length!==1||div[0]!==slot||calls[0]!==slot)throw Error('Header slot ID, body div ID and display(...) ID must match.');
 return {path:m[2],network:m[2].split('/')[1],slot,width:300,height:250};
}
if(typeof module!=='undefined')module.exports={parseGoogleTags};
