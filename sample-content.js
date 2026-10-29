/* Illustrative design-preview stories only. Never inserted into a publication database. */
window.ANJU_SAMPLE_TERMS=['Local','Politics','Society','Culture','Opinion','India'].map((name,i)=>({id:'sample-'+i,name,slug:name.toLowerCase(),kind:'category',menu_position:i+1}));
window.ANJU_SAMPLE_POSTS=[
 ['A city is more than its skyline. It is the people who call it home.','local','city','A closer look at neighbourhoods, public spaces and the small details that make everyday life work.'],
 ['The everyday conversations that deserve a bigger platform','society','community','Listening to community voices, asking better questions and making room for different perspectives.'],
 ['Between the headline and the whole story','opinion','desk','Why context matters, and how taking a second look can change our understanding of an issue.'],
 ['What makes a neighbourhood work for everyone?','local','community','An illustrative feature on shared spaces, accessibility and life in a growing city.'],
 ['A notebook, a question, and a story waiting to be told','culture','desk','Exploring the ideas and cultural moments that connect people across communities.'],
 ['Public life, seen from the street','politics','city','A sample newsroom story about the places where public decisions meet everyday experience.']
].map(([title,category,art,excerpt],i)=>({id:'10000000-0000-4000-8000-'+String(i+1).padStart(12,'0'),title,slug:'sample-story-'+(i+1),excerpt,status:'publish',published_at:new Date(Date.now()-i*3600000).toISOString(),featured_image_url:'/assets/demo/'+art+'.jpg',content_html:'<p>'+excerpt+'</p><p>This is an illustrative sample story created to preview the design of AnjuPankaj.com. It is not a published news report. Once the separate Supabase project is connected, only your publication’s saved and published posts will appear here.</p>',cms_post_terms:[{cms_terms:window.ANJU_SAMPLE_TERMS.find(t=>t.slug===category)}],sample:true}));
