const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc,deleteDoc}=require('firebase/firestore');
let env;
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-showdup',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{const db=c.firestore();await setDoc(doc(db,'users/alice'),{displayName:'Alice',stats:{completed:0},isPro:false});await setDoc(doc(db,'commitments/walk'),{ownerUid:'alice'});await setDoc(doc(db,'attempts/walk_2026-09-08'),{ownerUid:'alice',state:'pending'});await setDoc(doc(db,'attempts/walk_2026-09-08/events/fired:0'),{type:'fired'});});});
after(async()=>{await env.cleanup()});
test('owner reads succeed, cross-user and anonymous reads fail',async()=>{await assertSucceeds(getDoc(doc(env.authenticatedContext('alice').firestore(),'commitments/walk')));for(const db of [env.authenticatedContext('bob').firestore(),env.unauthenticatedContext().firestore()])for(const path of ['commitments/walk','attempts/walk_2026-09-08','users/alice'])await assertFails(getDoc(doc(db,path)));});
test('all attempt writes and client commitment writes denied',async()=>{const db=env.authenticatedContext('alice').firestore();for(const path of ['attempts/walk_2026-09-08','attempts/new','commitments/new'])await assertFails(setDoc(doc(db,path),{ownerUid:'alice',completedAt:new Date()}));await assertFails(updateDoc(doc(db,'commitments/walk'),{title:'Hijack'}));await assertFails(deleteDoc(doc(db,'commitments/walk')));await assertFails(deleteDoc(doc(db,'attempts/walk_2026-09-08')));});
test('attempt events are client-unreadable and unwritable',async()=>{const path='attempts/walk_2026-09-08/events/fired:0';for(const db of [env.authenticatedContext('alice').firestore(),env.authenticatedContext('bob').firestore(),env.unauthenticatedContext().firestore()]){await assertFails(getDoc(doc(db,path)));await assertFails(setDoc(doc(db,path),{type:'fired'}));await assertFails(setDoc(doc(db,'attempts/walk_2026-09-08/events/snoozed:1'),{type:'snoozed'}));await assertFails(deleteDoc(doc(db,path)));}});
test('protected profile updates denied',async()=>{const db=env.authenticatedContext('alice').firestore();for(const key of ['isPro','proExpiresAt','stats','completedAt','commitmentRevision','lastRevenueCatEventMs'])await assertFails(updateDoc(doc(db,'users/alice'),{[key]:true}));await assertSucceeds(updateDoc(doc(db,'users/alice'),{displayName:'Updated'}));await assertFails(deleteDoc(doc(db,'users/alice')));});
test('profile creation is an allowlist, including no completion timestamp',async()=>{const db=env.authenticatedContext('newuser').firestore();for(const key of ['isPro','proExpiresAt','stats','completedAt','commitmentRevision','lastRevenueCatEventMs'])await assertFails(setDoc(doc(db,'users/newuser'),{displayName:'New',[key]:true}));await assertFails(setDoc(doc(db,'users/newuser'),{displayName:'New',extra:'nope'}));await assertSucceeds(setDoc(doc(db,'users/newuser'),{displayName:'New',timezone:'Asia/Kolkata'}));});

test('callable transactions: cap races, idempotency, timestamps, ownership and abandoned attempts',async()=>{
 process.env.GCLOUD_PROJECT='demo-showdup';const api=require('../lib/index');const {getFirestore,Timestamp}=require('firebase-admin/firestore');const db=getFirestore();
 const u='functions-test';const auth={uid:u,token:{auth_time:Date.now()/1000}};
 const run=(name,data)=>api[name].run({data,auth});
 const good={title:'Walk',verifierType:'steps',verifierConfig:{targetSteps:200,minDurationMs:60000},schedule:{daysOfWeek:[1,2,3,4,5,6,7],windowStartLocal:'00:00',windowEndLocal:'23:59',timezone:'UTC'},reminder:{intervalMinutes:20,volumeMode:'gentle',maxReminders:6},restrictions:{enabled:false,packages:[]}};
 const results=await Promise.allSettled([run('createCommitment',good),run('createCommitment',good)]);assert.equal(results.filter(r=>r.status==='fulfilled').length,1);const cid=results.find(r=>r.status==='fulfilled').value.commitmentId;
 await assert.rejects(run('createCommitment',{...good,verifierConfig:{targetSteps:1}}));
 const date='2026-09-08',ref=db.doc(`attempts/${cid}_${date}`),base={commitmentId:cid,ownerUid:u,date,windowStartAt:Timestamp.fromMillis(Date.now()-600000),windowEndAt:Timestamp.fromMillis(Date.now()+600000),state:'pending',remindersFired:0,snoozes:0,createdAt:Timestamp.now()};await ref.set(base);
 const payload={stepsSinceBaseline:200,elapsedMs:120000,baselineCapturedAt:Date.now()-120000,completedAt:'1900-01-01'};const evidence={commitmentId:cid,date,type:'steps',payload,completedAt:'1900-01-01'};
 const first=await run('submitEvidence',evidence);assert.equal(first.state,'completed');assert.equal((await run('submitEvidence',evidence)).state,'completed');let snap=(await ref.get()).data();assert.ok(snap.completedAt.toMillis()>Date.now()-10000);assert.equal(snap.evidence.payload.completedAt,undefined);assert.equal((await db.doc(`users/${u}`).get()).data().stats.completed,1);
 await ref.set({...base,state:'abandoned'});await assert.rejects(run('submitEvidence',evidence));
 await ref.set({...base,windowEndAt:Timestamp.fromMillis(Date.now()-1000)});await assert.rejects(run('submitEvidence',evidence));
 await assert.rejects(run('endAttempt',{commitmentId:cid,date,reason:'verified'}));
 await ref.set(base);assert.equal((await run('endAttempt',{commitmentId:cid,date,reason:'user_ended'})).state,'abandoned');
 await assert.rejects(api.submitEvidence.run({data:evidence,auth:{uid:'other',token:{}}}));
 await assert.rejects(run('updateCommitment',{commitmentId:cid,patch:{ownerUid:'other'}}));
 await ref.set({...base,windowEndAt:Timestamp.fromMillis(Date.now()-1000)});await api.rolloverAttempts.run({});await api.rolloverAttempts.run({});assert.equal((await ref.get()).data().state,'expired');
});

test('server enforces the Pro active commitment cap',async()=>{
 const api=require('../lib/index'),{getFirestore,Timestamp}=require('firebase-admin/firestore'),db=getFirestore(),u='pro-cap-test',auth={uid:u,token:{auth_time:Date.now()/1000}},run=(name,data)=>api[name].run({data,auth});
 const good={title:'Walk',verifierType:'steps',verifierConfig:{targetSteps:200,minDurationMs:60000},schedule:{daysOfWeek:[1,2,3,4,5,6,7],windowStartLocal:'00:00',windowEndLocal:'23:59',timezone:'UTC'},reminder:{intervalMinutes:20,volumeMode:'gentle',maxReminders:6},restrictions:{enabled:false,packages:[]}};
 await db.doc(`users/${u}`).set({isPro:true});
 const batch=db.batch();for(let i=0;i<20;i++)batch.set(db.doc(`commitments/paid-${i}`),{...good,ownerUid:u,status:'active',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});batch.set(db.doc('commitments/paid-paused'),{...good,ownerUid:u,status:'paused',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});await batch.commit();
 await assert.rejects(run('createCommitment',good),e=>e.code==='resource-exhausted');
 await assert.rejects(run('updateCommitment',{commitmentId:'paid-paused',patch:{status:'active'}}),e=>e.code==='resource-exhausted');
});

test('reminder events are typed, idempotent and bounded by commitment policy',async()=>{
 const api=require('../lib/index'),{getFirestore,Timestamp}=require('firebase-admin/firestore'),db=getFirestore(),u='reminder-test',auth={uid:u,token:{auth_time:Date.now()/1000}},run=(data)=>api.recordReminderEvent.run({data,auth}),now=Date.now(),cid='reminder-commitment',aid='reminder-attempt';
 const good={title:'Walk',verifierType:'steps',verifierConfig:{targetSteps:200,minDurationMs:60000},schedule:{daysOfWeek:[1,2,3,4,5,6,7],windowStartLocal:'00:00',windowEndLocal:'23:59',timezone:'UTC'},reminder:{intervalMinutes:20,volumeMode:'gentle',maxReminders:1},restrictions:{enabled:false,packages:[]}};
 await db.doc(`commitments/${cid}`).set({...good,ownerUid:u,status:'active',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});await db.doc(`attempts/${aid}`).set({commitmentId:cid,ownerUid:u,date:'2026-09-08',windowStartAt:Timestamp.fromMillis(now-600000),windowEndAt:Timestamp.fromMillis(now+600000),state:'pending',remindersFired:0,snoozes:0,createdAt:Timestamp.now()});
 await run({attemptId:aid,type:'fired',eventId:'fired:0'});await run({attemptId:aid,type:'fired',eventId:'fired:0'});let attempt=(await db.doc(`attempts/${aid}`).get()).data();assert.equal(attempt.remindersFired,1);
 for(const data of [{attemptId:aid,type:'snoozed',eventId:'fired:0'},{attemptId:aid,type:'fired',eventId:'fired:1'},{attemptId:aid,type:'snoozed',eventId:`snoozed:${now+700000}`},{attemptId:aid,type:'fired',eventId:'fired:00'}])await assert.rejects(run(data),e=>e.code==='invalid-argument');
 await run({attemptId:aid,type:'snoozed',eventId:`snoozed:${now}`});await run({attemptId:aid,type:'snoozed',eventId:`snoozed:${now+1}`});attempt=(await db.doc(`attempts/${aid}`).get()).data();assert.equal(attempt.snoozes,1);assert.equal((await db.doc(`attempts/${aid}/events/snoozed:${now+1}`).get()).exists,false);
});

const baseCommitment={title:'Walk',verifierType:'steps',verifierConfig:{targetSteps:200,minDurationMs:60000},schedule:{daysOfWeek:[1,2,3,4,5,6,7],windowStartLocal:'00:00',windowEndLocal:'23:59',timezone:'UTC'},reminder:{intervalMinutes:20,volumeMode:'gentle',maxReminders:6},restrictions:{enabled:false,packages:[]}};
const admin=()=>{const api=require('../lib/index'),{getFirestore,Timestamp}=require('firebase-admin/firestore');return {api,db:getFirestore(),Timestamp,authApi:require('firebase-admin/auth').getAuth()};};
const pendingAttempt=(Timestamp,cid,ownerUid,start,end)=>({commitmentId:cid,ownerUid,date:'2026-09-08',windowStartAt:Timestamp.fromMillis(start),windowEndAt:Timestamp.fromMillis(end),state:'pending',remindersFired:0,snoozes:0,createdAt:Timestamp.now()});

test('pausing withdraws a not-yet-open attempt without stats, abandons an open one and expires a closed one',async()=>{
 const {api,db,Timestamp}=admin(),u='pause-test',run=(name,data)=>api[name].run({data,auth:{uid:u,token:{auth_time:Date.now()/1000}}}),now=Date.now();
 const mk=async(cid,start,end)=>{await db.doc(`commitments/${cid}`).set({...baseCommitment,ownerUid:u,status:'active',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});await db.doc(`attempts/${cid}_2026-09-08`).set(pendingAttempt(Timestamp,cid,u,start,end));};
 await mk('pause-future',now+1800000,now+3600000);await run('updateCommitment',{commitmentId:'pause-future',patch:{status:'paused'}});
 assert.equal((await db.doc('attempts/pause-future_2026-09-08').get()).exists,false);assert.equal((await db.doc(`users/${u}`).get()).data().stats,undefined);
 await mk('pause-open',now-600000,now+600000);await run('updateCommitment',{commitmentId:'pause-open',patch:{status:'paused'}});
 let a=(await db.doc('attempts/pause-open_2026-09-08').get()).data();assert.equal(a.state,'abandoned');assert.equal(a.endedReason,'user_ended');assert.equal((await db.doc(`users/${u}`).get()).data().stats.abandoned,1);
 await mk('pause-closed',now-7200000,now-3600000);await run('updateCommitment',{commitmentId:'pause-closed',patch:{status:'archived'}});
 a=(await db.doc('attempts/pause-closed_2026-09-08').get()).data();assert.equal(a.state,'expired');assert.equal(a.endedReason,'window_expired');assert.equal((await db.doc(`users/${u}`).get()).data().stats.abandoned,1);
});

test('late end or unable-to-verify calls cannot launder a closed window',async()=>{
 const {api,db,Timestamp}=admin(),u='late-test',auth={uid:u,token:{auth_time:Date.now()/1000}},now=Date.now();
 await db.doc(`users/${u}`).set({stats:{currentStreak:4,longestStreak:4,completed:4,abandoned:0,unverifiable:0}});
 await db.doc('attempts/late-c_2026-09-08').set(pendingAttempt(Timestamp,'late-c',u,now-7200000,now-1000));
 assert.equal((await api.reportVerifierFailure.run({data:{commitmentId:'late-c',date:'2026-09-08',reason:'sensor_lost'},auth})).state,'expired');
 assert.equal((await db.doc('attempts/late-c_2026-09-08').get()).data().endedReason,'window_expired');const st=(await db.doc(`users/${u}`).get()).data().stats;assert.equal(st.unverifiable,0);assert.equal(st.currentStreak,0);
 assert.equal((await api.endAttempt.run({data:{commitmentId:'late-c',date:'2026-09-08',reason:'user_ended'},auth})).state,'expired');
});

test('location evidence stores only whitelisted previous-fix fields and never a client completion time',async()=>{
 const {api,db,Timestamp}=admin(),u='loc-test',cid='loc-c',now=Date.now();
 await db.doc(`commitments/${cid}`).set({...baseCommitment,verifierType:'location',verifierConfig:{lat:19.07,lng:72.87,radiusM:150,dwellMs:60000},ownerUid:u,status:'paused',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
 await db.doc(`attempts/${cid}_2026-09-08`).set(pendingAttempt(Timestamp,cid,u,now-600000,now+600000));
 const payload={lat:19.07,lng:72.87,accuracyM:20,isMock:false,dwellMs:120000,epochMs:now,enteredAt:now-120000,previousFix:{lat:19.07,lng:72.87,epochMs:now-60000,junk:'x'.repeat(2000)},completedAt:'1900-01-01'};
 assert.equal((await api.submitEvidence.run({data:{commitmentId:cid,date:'2026-09-08',type:'location',payload},auth:{uid:u,token:{}}})).state,'completed');
 const a=(await db.doc(`attempts/${cid}_2026-09-08`).get()).data();assert.deepEqual(a.evidence.payload.previousFix,{lat:19.07,lng:72.87,epochMs:now-60000});assert.equal(a.evidence.payload.completedAt,undefined);assert.ok(a.completedAt.toMillis()>=now-10000);
});

test('RevenueCat webhook: secret, ordering, keep-until-expiry, unknown users, transient errors and transfers',async()=>{
 const {api,db,authApi}=admin(),known=new Set(['rc-a','rc-b','rc-c']),now=Date.now(),day=864e5;let authDown=false;process.env.REVENUECAT_WEBHOOK_AUTH='Bearer rc-test';
 authApi.getUser=async x=>{if(authDown)throw Object.assign(new Error('unavailable'),{code:'auth/internal-error'});if(!known.has(x))throw Object.assign(new Error('missing'),{code:'auth/user-not-found'});return {uid:x};};
 authApi.getUsers=async ids=>({users:ids.filter(i=>known.has(i.uid)).map(i=>({uid:i.uid})),notFound:ids.filter(i=>!known.has(i.uid))});
 const hook=async(event,key='Bearer rc-test')=>{const out={status:0,text:''},res={status(c){out.status=c;return res;},send(t){out.text=t;return res;},on(){},setHeader(){},getHeader(){},end(){}};await api.revenueCatWebhook({method:'POST',headers:{authorization:key},get:h=>h.toLowerCase()==='authorization'?key:undefined,body:{event}},res);return out;};
 const ev=(type,t,extra={})=>({id:`${type}-${t}`,type,app_user_id:'rc-a',event_timestamp_ms:t,entitlement_ids:['pro'],expiration_at_ms:now+day,...extra}),user=async x=>(await db.doc(`users/${x}`).get()).data();
 assert.equal((await hook(ev('INITIAL_PURCHASE',1000),'Bearer wrong')).status,401);assert.equal(await user('rc-a'),undefined);
 assert.equal((await hook(ev('INITIAL_PURCHASE',1000))).status,200);assert.equal((await user('rc-a')).isPro,true);
 await hook(ev('CANCELLATION',2000));let d=await user('rc-a');assert.equal(d.isPro,true);assert.equal(d.proExpiresAt.toMillis(),now+day);
 await hook(ev('RENEWAL',1500,{expiration_at_ms:now+30*day}));assert.equal((await user('rc-a')).proExpiresAt.toMillis(),now+day);
 await hook(ev('BILLING_ISSUE',3000,{expiration_at_ms:now-1000,grace_period_expiration_at_ms:now+3*day}));assert.equal((await user('rc-a')).isPro,true);
 await hook(ev('EXPIRATION',4000,{expiration_at_ms:now-1000}));assert.equal((await user('rc-a')).isPro,false);
 await hook(ev('NON_RENEWING_PURCHASE',4500,{expiration_at_ms:null}));d=await user('rc-a');assert.equal(d.isPro,true);assert.equal(d.proExpiresAt,null);
 await hook(ev('CANCELLATION',5000,{expiration_at_ms:null}));assert.equal((await user('rc-a')).isPro,false);
 assert.equal((await hook(ev('INITIAL_PURCHASE',6000,{entitlement_ids:['other']}))).text,'Ignored');
 for(const app_user_id of ['deleted-user','$RCAnonymousID:abc','a/b']){const r=await hook(ev('INITIAL_PURCHASE',6000,{app_user_id}));assert.equal(r.status,200);assert.equal(r.text,'Ignored unknown user');}
 assert.equal((await db.doc('users/deleted-user').get()).exists,false);
 authDown=true;assert.equal((await hook(ev('RENEWAL',7000))).status,500);assert.equal((await user('rc-a')).isPro,false);authDown=false;
 assert.equal((await hook({id:'bad'})).status,400);
 await hook(ev('RENEWAL',8000,{app_user_id:'rc-b',expiration_at_ms:now+10*day}));assert.equal((await user('rc-b')).isPro,true);
 assert.equal((await hook({id:'t1',type:'TRANSFER',event_timestamp_ms:9000,transferred_from:['rc-b'],transferred_to:['rc-c','$RCAnonymousID:zzz']})).status,200);
 assert.equal((await user('rc-b')).isPro,false);d=await user('rc-c');assert.equal(d.isPro,true);assert.equal(d.proExpiresAt.toMillis(),now+10*day);
 await hook({id:'t0',type:'TRANSFER',event_timestamp_ms:8500,transferred_from:['rc-c'],transferred_to:['rc-b']});assert.equal((await user('rc-c')).isPro,true);assert.equal((await user('rc-b')).isPro,false);
});

test('deleteAccount requires a recent sign-in and removes commitments, attempts with events, the profile and the auth user',async()=>{
 const {api,db,Timestamp,authApi}=admin(),u='delete-test',deleted=[];authApi.deleteUser=async x=>{deleted.push(x);if(deleted.length>1)throw Object.assign(new Error('gone'),{code:'auth/user-not-found'});};
 await db.doc(`users/${u}`).set({displayName:'D',stats:{completed:3}});await db.doc('commitments/del-c').set({...baseCommitment,ownerUid:u,status:'active',createdAt:Timestamp.now(),updatedAt:Timestamp.now()});
 const batch=db.batch();for(let i=0;i<120;i++)batch.set(db.doc(`attempts/del-c_${i}`),{...pendingAttempt(Timestamp,'del-c',u,Date.now()-1000,Date.now()+1000),state:'completed'});batch.set(db.doc('attempts/del-c_0/events/fired:0'),{type:'fired'});batch.set(db.doc('attempts/keep-other_2026-09-08'),{ownerUid:'someone-else',state:'pending'});await batch.commit();
 await assert.rejects(api.deleteAccount.run({data:{},auth:{uid:u,token:{auth_time:Date.now()/1000-600}}}),e=>e.code==='failed-precondition');assert.equal((await db.doc(`users/${u}`).get()).exists,true);
 const auth={uid:u,token:{auth_time:Date.now()/1000}};assert.deepEqual(await api.deleteAccount.run({data:{},auth}),{ok:true});
 for(const col of ['commitments','attempts'])assert.equal((await db.collection(col).where('ownerUid','==',u).get()).size,0);
 assert.equal((await db.doc(`users/${u}`).get()).exists,false);assert.equal((await db.doc('attempts/del-c_0/events/fired:0').get()).exists,false);assert.equal((await db.doc('attempts/keep-other_2026-09-08').get()).exists,true);assert.deepEqual(deleted,[u]);
 assert.deepEqual(await api.deleteAccount.run({data:{},auth}),{ok:true});
});

test('callables require a signed-in user',async()=>{
 const {api}=admin();
 await assert.rejects(api.syncAttempts.run({data:{}}),e=>e.code==='unauthenticated');
 await assert.rejects(api.deleteAccount.run({data:{}}),e=>e.code==='unauthenticated');
});

test('no attempt is minted that could not be completed, and lapsed Pro gets the free cap',async()=>{
 const {api,db,Timestamp}=admin(),now=Date.now(),today=new Date(now).toISOString().slice(0,10),endToday=Date.parse(`${today}T23:59:00Z`),as=u=>(name,data)=>api[name].run({data,auth:{uid:u,token:{auth_time:Date.now()/1000}}});
 const tight=await as('mint-tight')('createCommitment',{...baseCommitment,verifierConfig:{targetSteps:200,minDurationMs:Math.max(60000,Math.min(86400000,endToday-now+3600000))}});
 assert.equal((await db.doc(`attempts/${tight.commitmentId}_${today}`).get()).exists,false);
 if(endToday-now>120000){const ok=await as('mint-ok')('createCommitment',baseCommitment);assert.equal((await db.doc(`attempts/${ok.commitmentId}_${today}`).get()).exists,true);}
 await db.doc('users/pro-lapsed').set({isPro:true,proExpiresAt:Timestamp.fromMillis(now-1000)});await as('pro-lapsed')('createCommitment',baseCommitment);
 await assert.rejects(as('pro-lapsed')('createCommitment',baseCommitment),e=>e.code==='resource-exhausted'&&/^Free/.test(e.message));
});

test('one malformed commitment cannot stop rollover from expiring other attempts',async()=>{
 const {api,db,Timestamp}=admin();
 await db.doc('commitments/rollover-broken').set({...baseCommitment,ownerUid:'rollover-test',status:'active',schedule:{...baseCommitment.schedule,windowStartLocal:'10:00',windowEndLocal:'09:00'}});
 const ref=db.doc('attempts/rollover-ok_2026-09-08');await ref.set(pendingAttempt(Timestamp,'rollover-ok','rollover-test',Date.now()-7200000,Date.now()-1000));
 await api.rolloverAttempts.run({});assert.equal((await ref.get()).data().state,'expired');await db.doc('commitments/rollover-broken').delete();
});

