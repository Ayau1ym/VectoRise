import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import crypto from 'node:crypto';

const root = path.dirname(fileURLToPath(import.meta.url));
const dataDir = path.join(root, '.data');
const leadsFile = path.join(dataDir, 'leads.json');
try {
  const envText = await fs.readFile(path.join(root, '.env'), 'utf8');
  for (const line of envText.split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (match && !process.env[match[1]]) process.env[match[1]] = match[2].replace(/^(["'])(.*)\1$/, '$2');
  }
} catch {}
const port = Number(process.env.PORT || 4173);
const aiKey = process.env.AI_API_KEY || '';
const aiModel = process.env.AI_MODEL || 'gpt-4o-mini';
const aiBase = (process.env.AI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
const paymentUrl = process.env.PAYMENT_URL || '';
const adminToken = process.env.ADMIN_TOKEN || '';
const rates = new Map();
const mime = {'.html':'text/html; charset=utf-8','.css':'text/css; charset=utf-8','.js':'text/javascript; charset=utf-8','.json':'application/json; charset=utf-8','.svg':'image/svg+xml','.png':'image/png','.ico':'image/x-icon'};

function json(res,status,data){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data))}
function rateLimit(req,limit=20){const ip=req.socket.remoteAddress||'unknown';const now=Date.now();const entry=rates.get(ip)||{start:now,count:0};if(now-entry.start>60000){entry.start=now;entry.count=0}entry.count++;rates.set(ip,entry);return entry.count<=limit}
async function body(req,max=12000){let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>max)throw Object.assign(new Error('Request too large'),{status:413})}try{return JSON.parse(raw||'{}')}catch{throw Object.assign(new Error('Invalid JSON'),{status:400})}}
async function readLeads(){try{return JSON.parse(await fs.readFile(leadsFile,'utf8'))}catch{return []}}
async function route(req,res){
  const url=new URL(req.url,'http://localhost');
  if(req.method==='GET'&&url.pathname==='/api/status')return json(res,200,{aiEnabled:Boolean(aiKey),model:aiKey?aiModel:null,paymentEnabled:Boolean(paymentUrl),paymentUrl:paymentUrl||null});
  if(req.method==='POST'&&url.pathname==='/api/leads'){
    if(!rateLimit(req,8))return json(res,429,{error:'Слишком много заявок. Попробуйте позже.'});
    const input=await body(req,5000);const guardian=String(input.guardian||'').trim().slice(0,60);const email=String(input.email||'').trim().slice(0,120);const grade=String(input.grade||'').slice(0,24);
    if(input.consent!==true||guardian.length<2||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return json(res,400,{error:'Нужны имя взрослого представителя, действующий email и согласие на связь.'});
    await fs.mkdir(dataDir,{recursive:true});const leads=await readLeads();const lead={id:crypto.randomUUID(),guardian,email,grade,product:'Пилот 4 недели · 9 900 ₸',createdAt:new Date().toISOString(),consent:true};leads.push(lead);await fs.writeFile(leadsFile,JSON.stringify(leads,null,2),'utf8');return json(res,201,{ok:true,leadId:lead.id});
  }
  if(req.method==='GET'&&url.pathname==='/api/admin/leads'){
    if(!adminToken||req.headers['x-admin-token']!==adminToken)return json(res,401,{error:'Unauthorized'});
    return json(res,200,{leads:await readLeads()});
  }
  if(req.method==='POST'&&url.pathname==='/api/ai/chat'){
    if(!aiKey)return json(res,503,{error:'AI_API_KEY is not configured'});if(!rateLimit(req,30))return json(res,429,{error:'Слишком много сообщений. Подожди минуту.'});
    const input=await body(req,6000);const message=String(input.message||'').trim().slice(0,1000);if(!message)return json(res,400,{error:'Empty message'});
    const allowedProfile=input.profile&&typeof input.profile==='object'?{grade:String(input.profile.grade||'').slice(0,4),field:String(input.profile.field||'').slice(0,80),country:String(input.profile.country||'').slice(0,60),institution:String(input.profile.institution||'').slice(0,100),intake:String(input.profile.intake||'').slice(0,8),weeklyHours:String(input.profile.weeklyHours||'').slice(0,4),assets:Array.isArray(input.profile.assets)?input.profile.assets.slice(0,8).map(x=>String(x).slice(0,30)):[]}:{};
    const prompt=`Профиль ученика (без имени и контактов): ${JSON.stringify(allowedProfile)}\n\nВопрос: ${message}`;
    const response=await fetch(`${aiBase}/chat/completions`,{method:'POST',headers:{'Authorization':`Bearer ${aiKey}`,'Content-Type':'application/json'},body:JSON.stringify({model:aiModel,temperature:0.5,max_tokens:500,messages:[{role:'system',content:'Ты — спокойный помощник по образовательному планированию VectoRise для школьников Казахстана. Отвечай по-русски, просто и поддерживающе, в конкретных коротких шагах. Не выдумывай дедлайны и требования: направляй проверять официальные сайты. Не обещай поступление и не вычисляй шанс. Не пиши за ученика вступительное эссе; помогай планировать и улучшать его собственный черновик. Не проси личные данные.'},{role:'user',content:prompt}]})});
    if(!response.ok){const safe=await response.text();console.error('AI provider returned status',response.status,safe.slice(0,300));return json(res,502,{error:'AI provider unavailable'});}const result=await response.json();const reply=result.choices?.[0]?.message?.content;if(!reply)return json(res,502,{error:'Empty AI response'});return json(res,200,{reply:String(reply).slice(0,5000)});
  }
  if(req.method==='GET'&&url.pathname.startsWith('/api/'))return json(res,404,{error:'Not found'});
  if(req.method!=='GET'&&req.method!=='HEAD'){res.writeHead(405,{'Allow':'GET, HEAD'});return res.end('Method not allowed')}
  let pathname=decodeURIComponent(url.pathname);if(pathname==='/')pathname='/index.html';const target=path.resolve(root,`.${pathname}`);if(target!==root&&!target.startsWith(root+path.sep))return json(res,403,{error:'Forbidden'});
  try{const stat=await fs.stat(target);if(!stat.isFile())throw new Error('Not a file');const ext=path.extname(target).toLowerCase();res.writeHead(200,{'Content-Type':mime[ext]||'application/octet-stream','X-Content-Type-Options':'nosniff','Referrer-Policy':'strict-origin-when-cross-origin','Cache-Control':ext==='.html'?'no-cache':'public, max-age=3600'});if(req.method==='HEAD')return res.end();fs.createReadStream(target).pipe(res)}catch{return json(res,404,{error:'Not found'})}
}
const server=http.createServer((req,res)=>{route(req,res).catch(error=>{console.error(error);if(!res.headersSent)json(res,error.status||500,{error:error.status?error.message:'Server error'})})});
server.listen(port,'0.0.0.0',()=>console.log(`VectoRise is running at http://localhost:${port}`));
