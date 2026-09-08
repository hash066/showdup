const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,updateDoc}=require('firebase/firestore');
let env;
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-showdup',firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});await env.clearFirestore();await env.withSecurityRulesDisabled(async c=>{const db=c.firestore();await setDoc(doc(db,'users/alice'),{displayName:'Alice',stats:{completed:0},isPro:false});await setDoc(doc(db,'commitments/walk'),{ownerUid:'alice'});await setDoc(doc(db,'attempts/walk_2026-09-08'),{ownerUid:'alice',state:'pending'});});});
after(async()=>{await env.cleanup()});
test('owner reads succeed, cross-user and anonymous reads fail',async()=>{await assertSucceeds(getDoc(doc(env.authenticatedContext('alice').firestore(),'commitments/walk')));for(const db of [env.authenticatedContext('bob').firestore(),env.unauthenticatedContext().firestore()])for(const path of ['commitments/walk','attempts/walk_2026-09-08','users/alice'])await assertFails(getDoc(doc(db,path)));});
test('all attempt writes and client commitment writes denied',async()=>{const db=env.authenticatedContext('alice').firestore();for(const path of ['attempts/walk_2026-09-08','attempts/new','commitments/new'])await assertFails(setDoc(doc(db,path),{ownerUid:'alice',completedAt:new Date()}));});
test('protected profile updates denied',async()=>{const db=env.authenticatedContext('alice').firestore();for(const key of ['isPro','proExpiresAt','stats','completedAt','commitmentRevision'])await assertFails(updateDoc(doc(db,'users/alice'),{[key]:true}));await assertSucceeds(updateDoc(doc(db,'users/alice'),{displayName:'Updated'}));});
test('profile creation is an allowlist, including no completion timestamp',async()=>{const db=env.authenticatedContext('newuser').firestore();for(const key of ['isPro','proExpiresAt','stats','completedAt'])await assertFails(setDoc(doc(db,'users/newuser'),{displayName:'New',[key]:true}));await assertSucceeds(setDoc(doc(db,'users/newuser'),{displayName:'New',timezone:'Asia/Kolkata'}));});

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

