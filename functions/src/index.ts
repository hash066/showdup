import {initializeApp} from 'firebase-admin/app';
import {getAuth} from 'firebase-admin/auth';
import {getFirestore,FieldValue,Timestamp} from 'firebase-admin/firestore';
import {onCall,onRequest,HttpsError} from 'firebase-functions/v2/https';
import {onSchedule} from 'firebase-functions/v2/scheduler';
import {logger,setGlobalOptions} from 'firebase-functions/v2';
import {defineSecret} from 'firebase-functions/params';
import {timingSafeEqual} from 'node:crypto';
import {DateTime} from 'luxon';
import {z} from 'zod';
import {commitmentSchema,checkStepsPlausibility,checkLocationPlausibility,reminderEventSchema,parseReminderEvent} from './validation';
import {resolveWindow,nextStats,evidenceWindow,closingState,proFromEvent,carryPro} from './domain';
import {Commitment,Attempt,StepsConfig,LocationConfig,AttemptState,attemptId,FREE_MAX_ACTIVE_COMMITMENTS,PRO_MAX_ACTIVE_COMMITMENTS} from './types';
initializeApp();
// Explicit so a future SDK default change cannot silently move functions away from the region the
// Flutter (FirebaseFunctions.instance) and Kotlin (FirebaseFunctions.getInstance()) clients call.
setGlobalOptions({region:'us-central1'});
const db=getFirestore(),rcSecret=defineSecret('REVENUECAT_WEBHOOK_AUTH');
// Must equal AppConstants.entitlementPro (lib/core/constants.dart) and the RevenueCat dashboard entitlement identifier.
const PRO_ENTITLEMENT='pro',rcUid=/^[^/]{1,128}$/;
const id=z.string().regex(/^[A-Za-z0-9_-]{1,128}$/),dateSchema=z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(s=>DateTime.fromISO(s).isValid);
function uid(req:{auth?:{uid:string}}){if(!req.auth)throw new HttpsError('unauthenticated','Sign in to continue.');return req.auth.uid;}
function parse<T>(schema:z.ZodType<T>,data:unknown):T{const p=schema.safeParse(data);if(!p.success)throw new HttpsError('invalid-argument',p.error.issues.map(i=>i.message).join('. '));return p.data;}
function owner(data:FirebaseFirestore.DocumentData|undefined,u:string){if(!data||data.ownerUid!==u)throw new HttpsError('not-found','Not found.');}
const authMissing=(err:unknown)=>['auth/user-not-found','auth/invalid-uid'].includes(String((err as {code?:unknown})?.code));
// One bad document must never abort a whole scheduler run or a callable whose primary write already committed.
async function safely(label:string,fn:()=>Promise<unknown>){try{await fn();}catch(err){logger.error(label,{err:err instanceof Error?err.message:String(err)});}}
async function inBatches<T>(items:T[],fn:(t:T)=>Promise<unknown>,width=16){for(let i=0;i<items.length;i+=width)await Promise.all(items.slice(i,i+width).map(fn));}
async function ensureAttempt(cid:string,c:Commitment,now=Date.now()){
 const local=DateTime.fromMillis(now,{zone:c.schedule.timezone});
 for(const day of [local,local.plus({days:1})]){const date=day.toISODate()!,w=resolveWindow(c.schedule,date);if(!c.schedule.daysOfWeek.includes(w.weekday)||w.start>now+3600000||w.end<now)continue;
 const ref=db.doc(`attempts/${attemptId(cid,date)}`);await db.runTransaction(async tx=>{const s=await tx.get(ref);if(s.exists)return;tx.create(ref,{commitmentId:cid,ownerUid:c.ownerUid,date,windowStartAt:Timestamp.fromMillis(w.start),windowEndAt:Timestamp.fromMillis(w.end),state:'pending',remindersFired:0,snoozes:0,createdAt:FieldValue.serverTimestamp()});});}
}
// The attempt is also minted by syncAttempts/rolloverAttempts, so a failure here is logged rather than failing a committed write (a client retry would hit the cap).
const tryEnsure=(cid:string,c:Commitment,now=Date.now())=>safely(`ensureAttempt ${cid}`,()=>ensureAttempt(cid,c,now));
export const createCommitment=onCall({enforceAppCheck:true},async req=>{
 const u=uid(req),data=parse(commitmentSchema,req.data),ref=db.collection('commitments').doc();
 await db.runTransaction(async tx=>{const ur=db.doc(`users/${u}`),user=await tx.get(ur),active=await tx.get(db.collection('commitments').where('ownerUid','==',u).where('status','==','active')),limit=user.data()?.isPro?PRO_MAX_ACTIVE_COMMITMENTS:FREE_MAX_ACTIVE_COMMITMENTS;if(active.size>=limit)throw new HttpsError('resource-exhausted',user.data()?.isPro?'Pro includes up to 20 active commitments. Pause one first.':'Free includes one active commitment. Pause one or explore Pro.');tx.set(ur,{commitmentRevision:FieldValue.increment(1)},{merge:true});tx.create(ref,{...data,ownerUid:u,status:'active',createdAt:FieldValue.serverTimestamp(),updatedAt:FieldValue.serverTimestamp()});});
 await tryEnsure(ref.id,{...data,ownerUid:u,status:'active'} as Commitment);return {commitmentId:ref.id};
});
export const updateCommitment=onCall({enforceAppCheck:true},async req=>{
 const u=uid(req),cid=parse(id,req.data?.commitmentId),patch=req.data?.patch;
 if(!patch||typeof patch!=='object'||Array.isArray(patch)||Object.keys(patch).some(k=>!['title','verifierType','verifierConfig','schedule','reminder','restrictions','status'].includes(k)))throw new HttpsError('invalid-argument','Unsupported field.');
 const ref=db.doc(`commitments/${cid}`);await db.runTransaction(async tx=>{
 const snap=await tx.get(ref);owner(snap.data(),u);const c=snap.data() as Commitment,status=parse(z.enum(['active','paused','archived']),patch.status??c.status);
 if(c.status==='archived')throw new HttpsError('failed-precondition','Archived commitments cannot be changed.');
 const ur=db.doc(`users/${u}`),user=await tx.get(ur),active=await tx.get(db.collection('commitments').where('ownerUid','==',u).where('status','==','active')),pending=await tx.get(db.collection('attempts').where('commitmentId','==',cid).where('state','==','pending')),now=Date.now();
 if(pending.docs.some(d=>(d.data().windowStartAt as Timestamp).toMillis()<=now)&&Object.keys(patch).some(k=>k!=='status'&&k!=='title'))throw new HttpsError('failed-precondition','End today before changing an open window or verifier.');
 const limit=user.data()?.isPro?PRO_MAX_ACTIVE_COMMITMENTS:FREE_MAX_ACTIVE_COMMITMENTS;
 if(status==='active'&&c.status!=='active'&&active.size>=limit)throw new HttpsError('resource-exhausted',user.data()?.isPro?'Pro includes up to 20 active commitments. Pause one first.':'Free includes one active commitment.');
 const merged={...c,...patch},data=parse(commitmentSchema,Object.fromEntries(['title','verifierType','verifierConfig','schedule','reminder','restrictions'].map(k=>[k,merged[k]])));
 tx.update(ref,{...data,status,updatedAt:FieldValue.serverTimestamp()});let stats=user.data()?.stats;
 // Pausing/archiving ends an OPEN window as abandoned (or expired if it already closed); an attempt whose window has not opened
 // yet is simply withdrawn, so pausing ahead of time never costs a streak. Rescheduling an active commitment re-mints it below.
 for(const p of pending.docs){const a=p.data() as Attempt;if(status!=='active'&&a.windowStartAt.toMillis()<=now){const s=closingState('abandoned',now,a.windowEndAt.toMillis());tx.update(p.ref,{state:s,endedReason:s==='expired'?'window_expired':'user_ended'});stats=nextStats(stats,s);}else if(status!=='active'||Object.keys(patch).some(k=>!['title','status'].includes(k)))tx.delete(p.ref);}
 tx.set(ur,{commitmentRevision:FieldValue.increment(1),...(stats?{stats}:{})},{merge:true});});
 const latest=(await ref.get()).data() as Commitment;if(latest.status==='active')await tryEnsure(cid,latest);return {ok:true};
});
export const submitEvidence=onCall({enforceAppCheck:true},async req=>{
 const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,type:z.enum(['steps','location']),payload:z.record(z.unknown())}),req.data),aid=attemptId(a.commitmentId,a.date);
 return db.runTransaction(async tx=>{const ref=db.doc(`attempts/${aid}`),snap=await tx.get(ref),attempt=snap.data() as Attempt;owner(attempt,u);
 if(attempt.state==='completed')return {state:'completed',attemptId:aid};if(attempt.state!=='pending')throw new HttpsError('failed-precondition','This attempt has already ended.');
 const cs=await tx.get(db.doc(`commitments/${a.commitmentId}`)),c=cs.data() as Commitment;owner(c,u);if(c.verifierType!==a.type)throw new HttpsError('invalid-argument','Verifier does not match.');
 const now=Date.now(),start=attempt.windowStartAt.toMillis(),end=attempt.windowEndAt.toMillis(),p=a.payload,elapsed=Number(a.type==='steps'?p.elapsedMs:p.dwellMs);
 if(!evidenceWindow(now,start,end,elapsed))throw new HttpsError('failed-precondition','Evidence must be recorded within the open window.');
 let error:string|null,safe:Record<string,unknown>;
 if(a.type==='steps'){safe={stepsSinceBaseline:p.stepsSinceBaseline,elapsedMs:p.elapsedMs,baselineCapturedAt:p.baselineCapturedAt};if(typeof p.baselineCapturedAt!=='number'||p.baselineCapturedAt<start-5000||p.baselineCapturedAt>now||Math.abs(now-p.baselineCapturedAt-elapsed)>30000)throw new HttpsError('invalid-argument','Step baseline is outside this window.');error=checkStepsPlausibility({stepsSinceBaseline:p.stepsSinceBaseline as number,elapsedMs:p.elapsedMs as number,config:c.verifierConfig as StepsConfig});}
 else{const pf=p.previousFix as Record<string,unknown>|null|undefined;safe=Object.fromEntries(['lat','lng','accuracyM','isMock','dwellMs','epochMs','enteredAt'].filter(k=>p[k]!==undefined).map(k=>[k,p[k]]));if(pf&&typeof pf==='object')safe.previousFix={lat:pf.lat,lng:pf.lng,epochMs:pf.epochMs};if(typeof p.epochMs!=='number'||Math.abs(now-p.epochMs)>120000||typeof p.enteredAt!=='number'||p.enteredAt<start||p.epochMs-p.enteredAt<elapsed)throw new HttpsError('invalid-argument','Arrival and dwell must occur within this window.');error=checkLocationPlausibility({...safe,config:c.verifierConfig as LocationConfig} as Parameters<typeof checkLocationPlausibility>[0]);}
 if(error)throw new HttpsError('invalid-argument',error);const ur=db.doc(`users/${u}`),user=await tx.get(ur);tx.update(ref,{state:'completed',endedReason:'verified',completedAt:FieldValue.serverTimestamp(),evidence:{type:a.type,payload:safe,capturedAt:FieldValue.serverTimestamp(),confidence:'plausible'}});tx.set(ur,{stats:nextStats(user.data()?.stats,'completed')},{merge:true});return {state:'completed',attemptId:aid};});
});
async function finish(u:string,cid:string,date:string,state:AttemptState,reason:string){return db.runTransaction(async tx=>{const ref=db.doc(`attempts/${attemptId(cid,date)}`),snap=await tx.get(ref),a=snap.data() as Attempt;owner(a,u);if(a.state!=='pending')return {state:a.state};const s=closingState(state,Date.now(),a.windowEndAt.toMillis()),ur=db.doc(`users/${u}`),user=await tx.get(ur);tx.update(ref,{state:s,endedReason:s===state?reason:'window_expired'});tx.set(ur,{stats:nextStats(user.data()?.stats,s)},{merge:true});return {state:s};});}
export const endAttempt=onCall({enforceAppCheck:true},async req=>{const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,reason:z.literal('user_ended')}).strict(),req.data);return finish(u,a.commitmentId,a.date,'abandoned','user_ended');});
export const reportVerifierFailure=onCall({enforceAppCheck:true},async req=>{const u=uid(req),a=parse(z.object({commitmentId:id,date:dateSchema,reason:z.enum(['sensor_missing','permission_denied','sensor_lost','location_unavailable'])}).strict(),req.data);return finish(u,a.commitmentId,a.date,'unverifiable','verifier_error');});
export const syncAttempts=onCall({enforceAppCheck:true},async req=>{const u=uid(req),cs=await db.collection('commitments').where('ownerUid','==',u).where('status','==','active').get();for(const c of cs.docs)await tryEnsure(c.id,c.data() as Commitment);return {ok:true};});
export const recordReminderEvent=onCall({enforceAppCheck:true},async req=>{const u=uid(req),a=parse(reminderEventSchema,req.data);await db.runTransaction(async tx=>{
 const ref=db.doc(`attempts/${a.attemptId}`),s=await tx.get(ref),attempt=s.data() as Attempt;owner(attempt,u);if(attempt.state!=='pending')return;
 const commitmentSnap=await tx.get(db.doc(`commitments/${attempt.commitmentId}`)),commitment=commitmentSnap.data() as Commitment;owner(commitment,u);
 const parsed=parseReminderEvent(a.type,a.eventId,commitment.reminder.maxReminders,attempt.windowStartAt.toMillis(),attempt.windowEndAt.toMillis());if(!parsed)throw new HttpsError('invalid-argument','Invalid reminder event.');
 if(parsed.type==='fired'){
  const scheduledAt=attempt.windowStartAt.toMillis()+parsed.index*commitment.reminder.intervalMinutes*60000;
  if(scheduledAt>=attempt.windowEndAt.toMillis())throw new HttpsError('invalid-argument','Reminder is outside this attempt window.');
 }
 const event=ref.collection('events').doc(a.eventId),prior=await tx.get(event);if(prior.exists)return;
 const counter=a.type==='fired'?'remindersFired':'snoozes',count=Number(s.data()?.[counter]??0);if(!Number.isSafeInteger(count)||count<0||count>=commitment.reminder.maxReminders)return;
 tx.create(event,{type:a.type,at:FieldValue.serverTimestamp(),...(parsed.type==='fired'?{index:parsed.index}:{clientAt:Timestamp.fromMillis(parsed.clientAtMs)})});tx.update(ref,{[counter]:FieldValue.increment(1)});
 });return {ok:true};});
// Bounded fan-out, per-document error isolation and a time budget: one malformed commitment or a contended user document
// can no longer abort every later ensure/expiry, and expiry drains past the old 400-per-run cap. Expiries are grouped per
// user and applied sequentially within a user so parallel transactions never contend on the same users/{uid} stats doc.
export const rolloverAttempts=onSchedule({schedule:'every 15 minutes',timeoutSeconds:540},async()=>{
 const now=Date.now(),ensureBy=now+300000,expireBy=now+480000;let cursor:FirebaseFirestore.QueryDocumentSnapshot|undefined;
 do{let q=db.collection('commitments').where('status','==','active').orderBy('__name__').limit(200);if(cursor)q=q.startAfter(cursor);const page=await q.get();await inBatches(page.docs,c=>tryEnsure(c.id,c.data() as Commitment,now));cursor=page.size===200?page.docs.at(-1):undefined;}while(cursor&&Date.now()<ensureBy);
 let after:FirebaseFirestore.QueryDocumentSnapshot|undefined;
 do{let q=db.collection('attempts').where('state','==','pending').where('windowEndAt','<',Timestamp.fromMillis(now)).orderBy('windowEndAt').limit(400);if(after)q=q.startAfter(after);const page=await q.get(),byUser=new Map<string,Attempt[]>();
  for(const s of page.docs){const a=s.data() as Attempt;byUser.set(a.ownerUid,[...(byUser.get(a.ownerUid)??[]),a]);}
  await inBatches([...byUser.values()],async list=>{for(const a of list)await safely(`expire ${a.commitmentId}_${a.date}`,()=>finish(a.ownerUid,a.commitmentId,a.date,'expired','window_expired'));});
  after=page.size===400?page.docs.at(-1):undefined;}while(after&&Date.now()<expireBy);
});
const proFields=(p:{isPro:boolean;proExpiresAt:number|null},ts:number)=>({isPro:p.isPro,proExpiresAt:p.proExpiresAt===null?null:Timestamp.fromMillis(p.proExpiresAt),lastRevenueCatEventMs:ts});
const storedPro=(d:FirebaseFirestore.DocumentData|undefined)=>({isPro:d?.isPro,proExpiresAt:d?.proExpiresAt instanceof Timestamp?d.proExpiresAt.toMillis():null});
// TRANSFER (a restore on another Firebase account) carries no entitlement data: revoke Pro from the previous owners and carry
// their still-active entitlement to the new owner so neither account is left with a stale isPro.
async function transferPro(e:{transferred_from?:unknown;transferred_to?:unknown},ts:number){
 const ids=(v:unknown)=>Array.isArray(v)?v.filter((x):x is string=>typeof x==='string'&&rcUid.test(x)):[],from=ids(e.transferred_from),to=ids(e.transferred_to),all=[...new Set([...from,...to])].slice(0,100);if(!all.length)return;
 const {users}=await getAuth().getUsers(all.map(x=>({uid:x}))),refs=users.map(x=>db.doc(`users/${x.uid}`));if(!refs.length)return;
 await db.runTransaction(async tx=>{const snaps=await tx.getAll(...refs),now=Date.now(),carried=carryPro(snaps.filter(s=>from.includes(s.id)).map(s=>storedPro(s.data())),now);
  for(const s of snaps){if((s.data()?.lastRevenueCatEventMs??0)>=ts)continue;if(to.includes(s.id)){const best=carryPro([storedPro(s.data()),...(carried?[carried]:[])],now);if(best)tx.set(s.ref,proFields(best,ts),{merge:true});}else tx.set(s.ref,proFields({isPro:false,proExpiresAt:null},ts),{merge:true});}});
}
// Non-2xx makes RevenueCat retry. Only transient failures (500) should; unknown/deleted users and irrelevant events get 200 so
// they are not retried and never recreate a users/{uid} document for a deleted account.
export const revenueCatWebhook=onRequest({secrets:[rcSecret]},async(req,res)=>{
 const expected=Buffer.from(rcSecret.value()),actual=Buffer.from(req.get('authorization')??'');if(req.method!=='POST'||actual.length!==expected.length||!expected.length||!timingSafeEqual(actual,expected)){res.status(401).send('Unauthorized');return;}
 const e=req.body?.event,ts=e?.event_timestamp_ms;if(!e||typeof e.id!=='string'||typeof ts!=='number'||!Number.isFinite(ts)){res.status(400).send('Malformed event');return;}if(e.type==='TEST'){res.status(200).send('OK');return;}
 try{
  if(e.type==='TRANSFER'){await transferPro(e,ts);res.status(200).send('OK');return;}
  const ents=Array.isArray(e.entitlement_ids)?e.entitlement_ids:typeof e.entitlement_id==='string'?[e.entitlement_id]:[],next=proFromEvent(e,Date.now());
  if(!next||!ents.includes(PRO_ENTITLEMENT)){res.status(200).send('Ignored');return;}
  if(typeof e.app_user_id!=='string'||!rcUid.test(e.app_user_id)){logger.warn('RevenueCat event for non-Firebase user ignored',{eventId:e.id});res.status(200).send('Ignored unknown user');return;}
  try{await getAuth().getUser(e.app_user_id);}catch(err){if(!authMissing(err))throw err;logger.warn('RevenueCat event for unknown Firebase user ignored',{eventId:e.id});res.status(200).send('Ignored unknown user');return;}
  await db.runTransaction(async tx=>{const ur=db.doc(`users/${e.app_user_id}`),u=await tx.get(ur);if((u.data()?.lastRevenueCatEventMs??0)>=ts)return;tx.set(ur,proFields(next,ts),{merge:true});});res.status(200).send('OK');
 }catch(err){logger.error('RevenueCat webhook failed',{eventId:e.id,err:err instanceof Error?err.message:String(err)});res.status(500).send('Retry');}
});
// Commitments go first so no scheduler run can mint a new attempt mid-deletion; attempts are swept twice for any minted in between.
// Every step is idempotent, so a client retry after a partial failure (or after the auth user is already gone) completes the job.
export const deleteAccount=onCall({enforceAppCheck:true,timeoutSeconds:300},async req=>{const u=uid(req);if(Date.now()/1000-(req.auth?.token.auth_time??0)>300)throw new HttpsError('failed-precondition','Sign in again before deleting your account.');
 const bw=db.bulkWriter();try{for(const col of ['commitments','attempts','attempts']){let cursor:FirebaseFirestore.QueryDocumentSnapshot|undefined;do{let q=db.collection(col).where('ownerUid','==',u).orderBy('__name__').limit(200);if(cursor)q=q.startAfter(cursor);const page=await q.get();await inBatches(page.docs,s=>db.recursiveDelete(s.ref,bw),50);cursor=page.size===200?page.docs.at(-1):undefined;}while(cursor);}}finally{await bw.close();}
 await db.doc(`users/${u}`).delete();try{await getAuth().deleteUser(u);}catch(err){if(!authMissing(err))throw err;}return {ok:true};});
