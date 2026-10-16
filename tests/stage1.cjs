// Run only against a dedicated local QA account: this replaces that account's selected-day fixtures.
const {firefox}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert=require('node:assert/strict');
const base=process.env.REPLANIVA_API || 'http://127.0.0.1:8101';
const ui=process.env.REPLANIVA_UI || 'http://127.0.0.1:8100';
const email=process.env.REPLANIVA_TEST_EMAIL;
const password=process.env.REPLANIVA_TEST_PASSWORD;
assert(email && password && process.env.REPLANIVA_ADMIN_PASSWORD, 'Set dedicated QA account credentials and local admin password before running.');
(async()=>{
const browser=await firefox.launch({headless:true,...(process.env.FIREFOX_PATH ? {executablePath:process.env.FIREFOX_PATH} : {})});
const context=await browser.newContext({viewport:{width:1366,height:768}});const page=await context.newPage();const errors=[];page.on('pageerror',e=>errors.push(e.message));
const rpc=async(token,name,args={})=>{const r=await fetch(base+'/function/'+name,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(args)});const data=await r.json();return {status:r.status,value:data.data?.result,data};};
await page.goto(ui,{waitUntil:'networkidle'});
await page.getByLabel('Email',{exact:true}).fill(email);await page.getByLabel('Password',{exact:true}).fill(password);await page.getByRole('button',{name:'Sign in',exact:true}).click();
await page.getByRole('heading',{name:'Room for what matters'}).waitFor({timeout:30000});
const token=await page.evaluate(()=>localStorage.getItem('jac_token'));assert(token);
let board=(await rpc(token,'get_board')).value;assert(board,JSON.stringify(board));const day=board.day;
for(const t of board.tasks)assert((await rpc(token,'change_task',{task_id:t.id,operation:'delete'})).value.ok);
for(const c of board.commitments)assert((await rpc(token,'delete_commitment',{commitment_id:c.id})).value.ok);
await page.reload({waitUntil:'networkidle'});await page.getByRole('heading',{name:'Room for what matters'}).waitFor();
await page.getByRole('button',{name:'Hours',exact:true}).click();await page.getByLabel('Day starts').fill('08:00');await page.getByLabel('Day ends').fill('12:00');await page.getByLabel('Timezone (IANA)').fill('Africa/Nairobi');await page.getByRole('button',{name:'Save hours and schedule'}).click();await page.getByRole('status').filter({hasText:'Planning hours saved'}).waitFor();
await page.getByRole('button',{name:'Commitment',exact:true}).click();await page.getByLabel('Commitment title').fill('Team check-in');await page.getByLabel('Starts',{exact:true}).fill('09:00');await page.getByLabel('Ends',{exact:true}).fill('10:00');await page.getByRole('button',{name:'Save commitment and schedule'}).click();await page.getByRole('heading',{name:'Team check-in',exact:true}).waitFor();
await page.getByRole('button',{name:'Task',exact:true}).click();await page.getByLabel('Task title').fill('Prepare project brief');await page.getByLabel('Minutes needed').fill('90');await page.getByLabel('Due by').fill('12:00');await page.getByRole('button',{name:'Add task and schedule'}).click();await page.getByRole('heading',{name:'Prepare project brief',exact:true}).waitFor();
board=(await rpc(token,'get_board',{day})).value;assert.equal(board.timezone,'Africa/Nairobi');assert.equal(board.tasks[0].start,600);const task=board.tasks[0],fixed=board.commitments[0];
assert.equal((await rpc(null,'get_board',{day})).status,401);
for(const args of [{start:600,end:500,timezone:'UTC'},{start:0,end:1441,timezone:'UTC'},{start:480,end:720,timezone:'Bad/Zone'}])assert.equal((await rpc(token,'update_settings',args)).value.ok,false);
for(const zone of ['Pacific/Kiritimati','America/Adak']){assert((await rpc(token,'update_settings',{start:480,end:720,timezone:zone})).value.ok);const dated=(await rpc(token,'get_board')).value;const expected=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());assert.equal(dated.today,expected);}
assert((await rpc(token,'update_settings',{start:480,end:720,timezone:'Africa/Nairobi'})).value.ok);
assert.equal((await rpc(token,'save_commitment',{day,title:'Overlap',start:550,end:570})).value.ok,false);
assert.equal((await rpc(token,'save_task',{day,title:'Bad duration',duration:0,due_day:day,deadline:600})).value.ok,false);
assert((await rpc(token,'get_board',{day:'invalid-date'})).value.error);
assert((await rpc(token,'save_task',{day,title:'Cannot fit',duration:600,due_day:day,deadline:720})).value.ok);
board=(await rpc(token,'get_board',{day})).value;assert.equal(board.tasks.find(t=>t.title==='Cannot fit').start,-1);
const otherDay='2026-11-01';assert.equal((await rpc(token,'get_board',{day:otherDay})).value.tasks.length,0);
assert((await rpc(token,'save_task',{day,title:'Updated brief',duration:60,due_day:day,deadline:720,priority:3,task_id:task.id})).value.ok);
assert((await rpc(token,'change_task',{task_id:task.id,operation:'complete'})).value.ok);assert((await rpc(token,'get_board',{day})).value.tasks.find(t=>t.id===task.id).done);
assert((await rpc(token,'change_task',{task_id:task.id,operation:'reopen'})).value.ok);
assert((await rpc(token,'save_commitment',{day,title:'Team check-in updated',start:540,end:570,commitment_id:fixed.id})).value.ok);
// A temporary account checks cross-account IDs without exposing tokens in output.
const identity={type:'username',value:'stage1-isolation-'+Date.now()};const credential={type:'password',password:'Temporary-Isolation!2026'};
let res=await fetch(base+'/user/register',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({identities:[identity],credential})});assert.equal(res.status,201);
res=await fetch(base+'/user/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({identity,credential})});const second=(await res.json()).data.token;assert(second);
assert.equal((await rpc(second,'get_board',{day})).value.tasks.length,0);
assert.equal((await rpc(second,'change_task',{task_id:task.id,operation:'delete'})).value.ok,false);
assert.equal((await rpc(second,'save_task',{day,title:'Foreign edit',duration:30,due_day:day,deadline:720,task_id:task.id})).value.ok,false);
assert.equal((await rpc(second,'delete_commitment',{commitment_id:fixed.id})).value.ok,false);
assert.equal((await rpc(second,'save_commitment',{day,title:'Foreign edit',start:600,end:630,commitment_id:fixed.id})).value.ok,false);
// Built-in user deletion route is discovered from OpenAPI rather than guessed.
const spec=await (await fetch(base+'/openapi.json')).json();assert(spec.paths['/admin/users/{username}'].delete);
const adminLogin=await fetch(base+'/user/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({identity:{type:'username',value:process.env.REPLANIVA_ADMIN_USERNAME || 'admin'},credential:{type:'password',password:process.env.REPLANIVA_ADMIN_PASSWORD}})});
const adminToken=(await adminLogin.json()).data?.token;assert(adminToken,'Admin login required to clean up temporary isolation account');
const removed=await fetch(base+'/admin/users/'+encodeURIComponent(identity.value),{method:'DELETE',headers:{Authorization:'Bearer '+adminToken}});assert(removed.ok,'Temporary isolation account cleanup failed');
await page.reload({waitUntil:'networkidle'});await page.getByRole('heading',{name:'Updated brief',exact:true}).waitFor();await page.getByText('Cannot fit',{exact:true}).waitFor();
await page.screenshot({path:'/tmp/replaniva-stage1-desktop.png',fullPage:true});
for(const size of [{width:1280,height:540},{width:375,height:812},{width:812,height:375}]){await page.setViewportSize(size);const fits=await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth);if(!fits)console.log(await page.evaluate(()=>[...document.querySelectorAll('*')].filter(e=>e.getBoundingClientRect().right>innerWidth).map(e=>[e.tagName,e.className,e.getBoundingClientRect().width]).slice(0,12)));assert(fits,'horizontal overflow '+JSON.stringify(size));}
await page.emulateMedia({reducedMotion:'reduce'});await page.screenshot({path:'/tmp/replaniva-stage1-phone.png',fullPage:true});
await page.getByRole('button',{name:'Sign out',exact:true}).click();await page.getByRole('button',{name:'Sign in',exact:true}).waitFor();assert.equal(await page.evaluate(()=>localStorage.getItem('jac_token')),null);
assert.deepEqual(errors,[]);console.log('STAGE1_PASS browser, CRUD, settings, scheduling, validation, isolation, refresh, logout, responsive');await browser.close();
})().catch(e=>{console.error(e);process.exit(1)});
