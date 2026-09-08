import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore,FieldValue,Timestamp} from 'firebase-admin/firestore';
import {onCall,onRequest,HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {defineSecret} from 'firebase-functions/params';
import {timingSafeEqual} from 'node:crypto';
import {DateTime} from 'luxon';
import {z} from 'zod';
import {commitmentSchema,checkStepsPlausibility,checkLocationPlausibility} from './validation';
import {resolveWindow,nextStats,evidenceWindow} from './domain';
import {Commitment,Attempt,StepsConfig,LocationConfig,AttemptState,attemptId} from './types';
initializeApp();
const db=getFirestore(),rcSecret=defineSecret('REVENUECAT_WEBHOOK_AUTH');
const id=z.string().regex(/^[A-Za-z0-9_-]{1,128}$/),dateSchema=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s=>DateTime.fromISO(s).isValid);
function uid(req:{auth?:{uid:string}}){if(!req.auth)throw new HttpsError('unauthenticated','Sign in to continue.');return req.auth.uid;}
function parse<T>(schema:z.ZodType<T>,data:unknown):T{const p=schema.safeParse(data);if(!p.success)throw new HttpsError('invalid-argument',p.error.issues.map(i=>i.message).join('. '));return p.data;}
function owner(data:FirebaseFirestore.DocumentData|undefined,u:string){if(!data||data.ownerUid!==u)throw new HttpsError('not-found','Not found.');}
async function ensureAttempt(cid:string,c:Commitment,now=Date.now()){
 const local=DateTime.fromMillis(now,{zone:c.schedule.timezone});
 for(const day of [local,local.plus({days:1})]){const date=day.toISODate()!,w=resolveWindow(c.schedule,date);if(!c.schedule.daysOfWeek.includes(w.weekday)||w.start>now+3600000||w.end<now)continue;
 const ref=db.doc(`attempts/${attemptId(cid,date)}`);await db.runTransaction(async tx=>{const s=await tx.get(ref);if(s.exists)return;tx.create(ref,{commitmentId:cid,ownerUid:c.ownerUid,date,windowStartAt:Timestamp.fromMillis(w.start),windowEndAt:Timestamp.fromMillis(w.end),state:'pending',remindersFired:0,snoozes:0,createdAt:FieldValue.serverTimestamp()});});}
}
export const createCommitment=onCall(async req=>{
 const u=uid(req),data=parse(commitmentSchema,req.data),ref=db.collection('commitments').doc();
 await db.runTransaction(async tx=>{const ur=db.doc(`users/${u}`),user=await tx.get(ur),active=await tx.get(db.collection('commitments').where('ownerUid','==',u).where('status','==','active'));if(!user.data()?.isPro&&!active.empty)throw new HttpsError('resource-exhausted','Free includes one active commitment. Pause one or explore Pro.');tx.set(ur,{commitmentRevision:FieldValue.increment(1)},{merge:true});tx.create(ref,{...data,ownerUid:u,status:'active',createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});});
 await ensureAttempt(ref.id,{...data,ownerUid:u,status:'active'} as Commitment);return {commitmentId:ref.id};
});
export const updateCommitment=onCall(async req=>{
 const u=uid(req),cid=parse(id,req.data?.commitmentId),patch=req.data?.patch;
 if(!patch||typeof patch!=='object'||Array.isArray(patch)||Object.keys(patch).some(k=>!['title','verifierType','verifierConfig','schedule','reminder','restrictions','status'].includes(k)))throw new HttpsError('invalid-argument','Unsupported field.');
 const ref=db.doc(`commitments/${cid}`);await db.runTransaction(async tx=>{
 const snap=await tx.get(ref);owner(snap.data(),u);const c=snap.data() as Commitment,status=parse(z.enum(['active','paused','archived']),patch.status??c.status);
 if(c.status==='archived')throw new HttpsError('failed-precondition','Archived commitments cannot be changed.');
 const ur=db.doc(`users/${u}`),user=await tx.get(ur),active=await tx.get(db.collection('commitments').where('ownerUid','==',u).where('status','==','active')),pending=await tx.get(db.collection('attempts').where('commitmentId','==',cid).where('state','==','pending'));
 if(pending.docs.some(d=>(d.data().windowStartAt as Timestamp).toMillis()<=Date.now())&&Object.keys(patch).some(k=>k!=='status'&&k!=='title'))throw new HttpsError('failed-precondition','End today before changing an open window or verifier.');
 if(status==='active'&&c.status!=='active'&&!user.data()?.isPro&&!active.empty)throw new HttpsError('resource-exhausted','Free includes one active commitment.');
 const merged={...c,...patch},data=parse(commitmentSchema,Object.fromEntries(['title','verifierType','verifierConfig','schedule','reminder','restrictions'].map(k=>[k,merged[k]])));
 tx.update(ref,{...data,status,updatedAt:FieldValue.serverTimestamp()});let stats=user.data()?.stats;
 for(const p of pending.docs){if(status!=='active'){tx.update(p.ref,{state:'abandoned',endedReason:'user_ended'});stats=nextStats(stats,'abandoned');}else if(Object.keys(patch).some(k=>!['title','status'].includes(k)))tx.delete(p.ref);}
 tx.set(ur,{commitmentRevision:FieldValue.increment(1),...(stats?{stats}:{})},{merge:true});});
 const latest=(await ref.get()).data() as Commitment;if(latest.status==='active')await ensureAttempt(cid,latest);return {ok:true};
});
export const submitEvidence=onCall(async req=>{
 const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,type:z.enum(['steps','location']),payload:z.record(z.unknown())}),req.data),aid=attemptId(a.commitmentId,a.date);
 return db.runTransaction(async tx=>{const ref=db.doc(`attempts/${aid}`),snap=await tx.get(ref),attempt=snap.data() as Attempt;owner(attempt,u);
 if(attempt.state==='completed')return {state:'completed',attemptId:aid};if(attempt.state!=='pending')throw new HttpsError('failed-precondition','This attempt has already ended.');
 const cs=await tx.get(db.doc(`commitments/${a.commitmentId}`)),c=cs.data() as Commitment;owner(c,u);if(c.verifierType!==a.type)throw new HttpsError('invalid-argument','Verifier does not match.');
 const now=Date.now(),start=attempt.windowStartAt.toMillis(),end=attempt.windowEndAt.toMillis(),p=a.payload,elapsed=Number(a.type==='steps'?p.elapsedMs:p.dwellMs);
 if(!evidenceWindow(now,start,end,elapsed))throw new HttpsError('failed-precondition','Evidence must be recorded within the open window.');
 let error:string|null,safe:Record<string,unknown>;
 if(a.type==='steps'){safe={stepsSinceBaseline:p.stepsSinceBaseline,elapsedMs:p.elapsedMs,baselineCapturedAt:p.baselineCapturedAt};if(typeof p.baselineCapturedAt!=='number'||p.baselineCapturedAt<start-5000||p.baselineCapturedAt>now||Math.abs(now-p.baselineCapturedAt-elapsed)>30000)throw new HttpsError('invalid-argument','Step baseline is outside this window.');error=checkStepsPlausibility({stepsSinceBaseline:p.stepsSinceBaseline as number,elapsedMs:p.elapsedMs as number,config:c.verifierConfig as StepsConfig});}
 else{safe=Object.fromEntries(['lat','lng','accuracyM','isMock','dwellMs','previousFix','epochMs','enteredAt'].filter(k=>p[k]!==undefined).map(k=>[k,p[k]]));if(typeof p.epochMs!=='number'||Math.abs(now-p.epochMs)>120000||typeof p.enteredAt!=='number'||p.enteredAt<start||p.epochMs-p.enteredAt<elapsed)throw new HttpsError('invalid-argument','Arrival and dwell must occur within this window.');error=checkLocationPlausibility({...safe,config:c.verifierConfig as LocationConfig} as Parameters<typeof checkLocationPlausibility>[0]);}
 if(error)throw new HttpsError('invalid-argument',error);const ur=db.doc(`users/${u}`),user=await tx.get(ur);tx.update(ref,{state:'completed',endedReason:'verified',completedAt:FieldValue.serverTimestamp(),evidence:{type:a.type,payload:safe,capturedAt:FieldValue.serverTimestamp(),confidence:'plausible'}});tx.set(ur,{stats:nextStats(user.data()?.stats,'completed')},{merge:true});return {state:'completed',attemptId:aid};});
});
async function finish(u:string,cid:string,date:string,state:AttemptState,reason:string){return db.runTransaction(async tx=>{const ref=db.doc(`attempts/${attemptId(cid,date)}`),snap=await tx.get(ref),a=snap.data() as Attempt;owner(a,u);if(a.state!=='pending')return {state:a.state};const ur=db.doc(`users/${u}`),user=await tx.get(ur);tx.update(ref,{state,endedReason:reason});tx.set(ur,{stats:nextStats(user.data()?.stats,state)},{merge:true});return {state};});}
export const endAttempt=onCall(async req=>{const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,reason:z.literal('user_ended')}).strict(),req.data);return finish(u,a.commitmentId,a.date,'abandoned','user_ended');});
export const reportVerifierFailure=onCall(async req=>{const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,reason:z.enum(['sensor_missing','permission_denied','sensor_lost','location_unavailable'])}).strict(),req.data);return finish(u,a.commitmentId,a.date,'unverifiable','verifier_error');});
export const syncAttempts=onCall(async req=>{const u=uid(req),cs=await db.collection('commitments').where('ownerUid','==',u).where('status','==','active').get();for(const c of cs.docs)await ensureAttempt(c.id,c.data() as Commitment);return {ok:true};});
export const recordReminderEvent=onCall(async req=>{const u=uid(req),a=parse(z.object({attemptId:id,eventId:z.string().min(1).max(160),type:z.enum(['fired','snoozed'])}),req.data);await db.runTransaction(async tx=>{const ref=db.doc(`attempts/${a.attemptId}`),s=await tx.get(ref);owner(s.data(),u);const event=ref.collection('events').doc(a.eventId.replace(/\//g,'_')),prior=await tx.get(event);if(prior.exists||s.data()?.state!=='pending')return;tx.create(event,{type:a.type,at:FieldValue.serverTimestamp()});tx.update(ref,{[a.type==='fired'?'remindersFired':'snoozes']:FieldValue.increment(1)});});return {ok:true};});
export const rolloverAttempts=onSchedule('every 15 minutes',async()=>{const now=Date.now();let cursor:FirebaseFirestore.QueryDocumentSnapshot|undefined;do{let q=db.collection('commitments').where('status','==','active').orderBy('__name__').limit(200);if(cursor)q=q.startAfter(cursor);const page=await q.get();for(const c of page.docs)await ensureAttempt(c.id,c.data() as Commitment,now);cursor=page.size===200?page.docs.at(-1):undefined;}while(cursor);const expired=await db.collection('attempts').where('state','==','pending').where('windowEndAt','<',Timestamp.fromMillis(now)).limit(400).get();for(const s of expired.docs){const a=s.data() as Attempt;await finish(a.ownerUid,a.commitmentId,a.date,'expired','window_expired');}});
export const revenueCatWebhook=onRequest({secrets:[rcSecret]},async(req,res)=>{
 const expected=Buffer.from(rcSecret.value()),actual=Buffer.from(req.get('authorization')??'');if(req.method!=='POST'||actual.length!==expected.length||!expected.length||!timingSafeEqual(actual,expected)){res.status(401).send('Unauthorized');return;}
 const e=req.body?.event;if(!e||typeof e.id!=='string'||typeof e.app_user_id!=='string'||!Number.isFinite(e.event_timestamp_ms)){res.status(400).send('Malformed event');return;}if(e.type==='TEST'){res.status(200).send('OK');return;}if(!e.entitlement_ids?.includes('pro')||!['INITIAL_PURCHASE','RENEWAL','UNCANCELLATION','NON_RENEWING_PURCHASE','PRODUCT_CHANGE','CANCELLATION','BILLING_ISSUE','EXPIRATION'].includes(e.type)){res.status(200).send('Ignored');return;}
 try{await getAuth().getUser(e.app_user_id);}catch{res.status(400).send('Unknown Firebase user');return;}
 await db.runTransaction(async tx=>{const ur=db.doc(`users/${e.app_user_id}`),u=await tx.get(ur);if((u.data()?.lastRevenueCatEventMs??0)>=e.event_timestamp_ms)return;const expiry=e.expiration_at_ms,isPro=e.type!=='EXPIRATION'&&(expiry===null||Number.isFinite(expiry)&&expiry>Date.now());tx.set(ur,{isPro,proExpiresAt:Number.isFinite(expiry)?Timestamp.fromMillis(expiry):null,lastRevenueCatEventMs:e.event_timestamp_ms},{merge:true});});res.status(200).send('OK');
});
export const deleteAccount=onCall(async req=>{const u=uid(req);if(Date.now()/1000-(req.auth?.token.auth_time??0)>300)throw new HttpsError('failed-precondition','Sign in again before deleting your account.');for(const col of ['attempts','commitments']){const ss=await db.collection(col).where('ownerUid','==',u).get();for(const s of ss.docs)await db.recursiveDelete(s.ref);}await db.doc(`users/${u}`).delete();await getAuth().deleteUser(u);return {ok:true};});
