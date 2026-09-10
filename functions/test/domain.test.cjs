const {test}=require('node:test');
const assert=require('node:assert/strict');
const {resolveWindow,nextStats,evidenceWindow,closingState,proFromEvent,carryPro,requiredMs,mintable,sameSchedule,hasPro}=require('../lib/domain');
const {commitmentSchema,checkStepsPlausibility,checkLocationPlausibility,reminderEventSchema,parseReminderEvent}=require('../lib/validation');
const schedule={daysOfWeek:[1,2,3,4,5],windowStartLocal:'06:30',windowEndLocal:'09:00',timezone:'Asia/Kolkata'};
const config={targetSteps:1000,minDurationMs:60000};
test('Kolkata 06:30 resolves to 01:00 UTC independent of device timezone',()=>assert.equal(new Date(resolveWindow(schedule,'2026-09-08').start).toISOString(),'2026-09-08T01:00:00.000Z'));
test('DST preserves local schedule',()=>assert.equal(new Date(resolveWindow({...schedule,timezone:'America/New_York'},'2026-07-01').start).toISOString(),'2026-07-01T10:30:00.000Z'));
test('unverifiable preserves streak and awards nothing',()=>{const s=nextStats({currentStreak:7,completed:10},'unverifiable');assert.equal(s.currentStreak,7);assert.equal(s.completed,10);assert.equal(s.unverifiable,1)});
test('expired and abandoned break streak, completed increments',()=>{assert.equal(nextStats({currentStreak:7},'expired').currentStreak,0);assert.equal(nextStats({currentStreak:7},'abandoned').currentStreak,0);assert.equal(nextStats({currentStreak:7},'completed').longestStreak,8)});
test('step evidence rejects short duration, superhuman pace, NaN and below target',()=>{for(const [stepsSinceBaseline,elapsedMs]of [[5000,30000],[3000,600000],[999,600000],[NaN,600000],[50001,36000000]])assert.ok(checkStepsPlausibility({stepsSinceBaseline,elapsedMs,config}));assert.equal(checkStepsPlausibility({stepsSinceBaseline:1000,elapsedMs:600000,config}),null)});
test('duration cannot predate attempt window',()=>{assert.equal(evidenceWindow(1000000,900000,1100000,600000),false);assert.equal(evidenceWindow(1000000,900000,1100000,60000),true);assert.equal(evidenceWindow(1200000,900000,1100000,60000),false)});
const fix={lat:19.07,lng:72.87,accuracyM:20,isMock:false,dwellMs:300000,epochMs:1000000,previousFix:{lat:19.07,lng:72.87,epochMs:940000},config:{lat:19.07,lng:72.87,radiusM:150,dwellMs:300000}};
test('location needs real accurate arrival plus dwell',()=>{assert.equal(checkLocationPlausibility(fix),null);for(const patch of [{isMock:true},{accuracyM:151},{dwellMs:0},{previousFix:undefined},{lat:20},{previousFix:{lat:0,lng:0,epochMs:999999}},{lat:NaN}])assert.ok(checkLocationPlausibility({...fix,...patch}))});
test('commitment validates strict schemas, timezone, schedule and deferred blocking',()=>{const good={title:'Walk',verifierType:'steps',verifierConfig:config,schedule,reminder:{intervalMinutes:20,volumeMode:'gentle',maxReminders:6},restrictions:{enabled:false,packages:[]}};assert.equal(commitmentSchema.safeParse(good).success,true);for(const patch of [{title:''},{ownerUid:'attacker'},{verifierConfig:{targetSteps:1,minDurationMs:60000}},{schedule:{...schedule,timezone:'Nowhere/Invalid'}},{schedule:{...schedule,windowEndLocal:'06:31'}},{restrictions:{enabled:true,packages:['a']}}])assert.equal(commitmentSchema.safeParse({...good,...patch}).success,false)});
test('reminder event identifiers are strict, typed and policy bounded',()=>{
 const start=1800000000000,end=start+3600000;
 assert.deepEqual(parseReminderEvent('fired','fired:0',2,start,end),{type:'fired',index:0});
 assert.deepEqual(parseReminderEvent('snoozed',`snoozed:${start}`,2,start,end),{type:'snoozed',clientAtMs:start});
 for(const [type,eventId] of [['fired','fired:2'],['fired','fired:00'],['fired','snoozed:1800000000000'],['snoozed','snoozed:1'],['snoozed',`snoozed:${end+1}`],['snoozed','fired:0']])assert.equal(parseReminderEvent(type,eventId,2,start,end),null);
 assert.equal(reminderEventSchema.safeParse({attemptId:'valid_attempt-1',eventId:'fired:0',type:'fired'}).success,true);
 for(const bad of [{attemptId:'bad/path',eventId:'fired:0',type:'fired'},{attemptId:'ok',eventId:'fired:0',type:'fired',extra:true},{attemptId:'ok',eventId:'x'.repeat(65),type:'fired'}])assert.equal(reminderEventSchema.safeParse(bad).success,false);
});
test('a closed window always closes as expired',()=>{assert.equal(closingState('unverifiable',1001,1000),'expired');assert.equal(closingState('abandoned',1001,1000),'expired');assert.equal(closingState('abandoned',1000,1000),'abandoned');assert.equal(closingState('unverifiable',5,1000),'unverifiable')});
test('RevenueCat: cancellation and billing issue keep Pro until expiry; expiration, refunds and missing expiry revoke',()=>{
 const now=1e12,day=864e5;
 assert.deepEqual(proFromEvent({type:'INITIAL_PURCHASE',expiration_at_ms:now+day},now),{isPro:true,proExpiresAt:now+day});
 assert.deepEqual(proFromEvent({type:'CANCELLATION',expiration_at_ms:now+day},now),{isPro:true,proExpiresAt:now+day});
 assert.deepEqual(proFromEvent({type:'CANCELLATION',expiration_at_ms:now-1},now),{isPro:false,proExpiresAt:now-1});
 assert.deepEqual(proFromEvent({type:'CANCELLATION',expiration_at_ms:null},now),{isPro:false,proExpiresAt:null});
 assert.deepEqual(proFromEvent({type:'BILLING_ISSUE',expiration_at_ms:now-1,grace_period_expiration_at_ms:now+day},now),{isPro:true,proExpiresAt:now+day});
 assert.deepEqual(proFromEvent({type:'NON_RENEWING_PURCHASE',expiration_at_ms:null},now),{isPro:true,proExpiresAt:null});
 assert.deepEqual(proFromEvent({type:'RENEWAL'},now),{isPro:false,proExpiresAt:null});
 assert.deepEqual(proFromEvent({type:'RENEWAL',expiration_at_ms:String(now+day)},now),{isPro:false,proExpiresAt:null});
 assert.deepEqual(proFromEvent({type:'EXPIRATION',expiration_at_ms:now+day},now),{isPro:false,proExpiresAt:now+day});
 for(const type of ['SUBSCRIPTION_EXTENDED','TEMPORARY_ENTITLEMENT_GRANT','REFUND_REVERSED','UNCANCELLATION','PRODUCT_CHANGE','SUBSCRIPTION_PAUSED'])assert.equal(proFromEvent({type,expiration_at_ms:now+day},now).isPro,true);
 for(const type of ['TRANSFER','TEST','INVOICE_ISSUANCE',undefined])assert.equal(proFromEvent({type,expiration_at_ms:now+day},now),null);
});
test('attempts are minted only when the remaining window can still satisfy the verifier',()=>{
 const m=60000,h=60*m,now=1e12;assert.equal(requiredMs('steps',{minDurationMs:30*m}),30*m);assert.equal(requiredMs('location',{dwellMs:5*m}),5*m);assert.equal(requiredMs('steps',{}),m);
 assert.equal(mintable({start:now-110*m,end:now+10*m},now,30*m),false);assert.equal(mintable({start:now-90*m,end:now+30*m},now,30*m),true);
 assert.equal(mintable({start:now+30*m,end:now+40*m},now,30*m),false);assert.equal(mintable({start:now+30*m,end:now+2*h},now,30*m),true);assert.equal(mintable({start:now+2*h,end:now+3*h},now,m),false);assert.equal(mintable({start:now-2*h,end:now-1},now,m),false);
});
test('schedule identity ignores key order; Pro stops at its stored expiry',()=>{
 assert.equal(sameSchedule(schedule,{timezone:'Asia/Kolkata',windowEndLocal:'09:00',windowStartLocal:'06:30',daysOfWeek:[1,2,3,4,5]}),true);assert.equal(sameSchedule(schedule,{...schedule,windowStartLocal:'07:00'}),false);assert.equal(sameSchedule(schedule,{...schedule,daysOfWeek:[1,2]}),false);
 const at=ms=>({toMillis:()=>ms});assert.equal(hasPro({isPro:true,proExpiresAt:null},1000),true);assert.equal(hasPro({isPro:true,proExpiresAt:at(2000)},1000),true);assert.equal(hasPro({isPro:true,proExpiresAt:at(1000)},1000),false);assert.equal(hasPro({isPro:'true'},1000),false);assert.equal(hasPro(undefined,1000),false);
});
test('transfer carries only the best still-active entitlement',()=>{const now=1000;assert.equal(carryPro([{isPro:false,proExpiresAt:null},{isPro:true,proExpiresAt:999},{isPro:'true',proExpiresAt:5000}],now),null);assert.deepEqual(carryPro([{isPro:true,proExpiresAt:2000},{isPro:true,proExpiresAt:5000}],now),{isPro:true,proExpiresAt:5000});assert.deepEqual(carryPro([{isPro:true,proExpiresAt:5000},{isPro:true,proExpiresAt:null}],now),{isPro:true,proExpiresAt:null})});
