#!/bin/bash
# Lee los mensajes que llegan por el formulario de nightfix-dev.netlify.app
netlify api listSiteSubmissions --data '{"site_id":"8eb43d87-6c76-4e9a-89b3-7876dcb194ec"}' 2>/dev/null \
| node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const s=JSON.parse(d);
if(!s.length){console.log('bandeja vacía');process.exit(0)}
s.forEach(x=>console.log('---\n'+x.created_at+'  '+x.data.email+'  ['+(x.data.urgency||'')+']\n'+(x.data.problem||'')))})"
