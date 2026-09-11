import {DateTime} from 'luxon';
import {CommitmentSchedule,UserStats,AttemptState,VerifierType} from './types';
export function resolveWindow(s:CommitmentSchedule,date:string){const start=DateTime.fromISO(`${date}T${s.windowStartLocal}`,{zone:s.timezone}),end=DateTime.fromISO(`${date}T${s.windowEndLocal}`,{zone:s.timezone});if(!start.isValid||!end.isValid||end<=start)throw new Error('Invalid window');return {start:start.toMillis(),end:end.toMillis(),weekday:start.weekday};}
export const emptyStats:UserStats={currentStreak:0,longestStreak:0,completed:0,abandoned:0,unverifiable:0};
export function nextStats(current:Partial<UserStats>|undefined,state:AttemptState):UserStats{const s={...emptyStats,...current};if(state==='completed'){s.completed++;s.currentStreak++;s.longestStreak=Math.max(s.longestStreak,s.currentStreak);}if(state==='abandoned'){s.abandoned++;s.currentStreak=0;}if(state==='expired')s.currentStreak=0;if(state==='unverifiable')s.unverifiable++;return s;}
// Evidence must span this long inside the window (see check*Plausibility), so a window with less time left can never complete.
export function requiredMs(type:VerifierType,cfg:{minDurationMs?:unknown;dwellMs?:unknown}){return Math.max(60000,Number(type==='steps'?cfg.minDurationMs:cfg.dwellMs)||0);}
// Mint at most an hour ahead, and never an attempt that would expire (and cost a streak) before it could be satisfied.
export function mintable(w:{start:number;end:number},now:number,required:number){return w.start<=now+3600000&&w.end-Math.max(now,w.start)>=required;}
export function sameSchedule(a:CommitmentSchedule,b:CommitmentSchedule){return a.windowStartLocal===b.windowStartLocal&&a.windowEndLocal===b.windowEndLocal&&a.timezone===b.timezone&&a.daysOfWeek.join()===b.daysOfWeek.join();}
// isPro is trusted only until its stored expiry, so a lost EXPIRATION webhook cannot keep Pro limits forever.
export function hasPro(d:{isPro?:unknown;proExpiresAt?:unknown}|undefined,now:number){const x=d?.proExpiresAt as {toMillis?:()=>number}|null|undefined;return d?.isPro===true&&!(x&&typeof x.toMillis==='function'&&x.toMillis()<=now);}
export function evidenceWindow(now:number,start:number,end:number,elapsed:number){return now>=start&&now<=end&&Number.isFinite(elapsed)&&elapsed>=0&&elapsed<=now-start+5000;}
// Once a window has closed the outcome is 'expired'; a late end/unable call cannot launder it into a different state.
export function closingState(requested:AttemptState,now:number,windowEndMs:number):AttemptState{return now>windowEndMs?'expired':requested;}
// RevenueCat entitlement state. GRANT events with an explicit null expiration are lifetime purchases;
// CANCELLATION/BILLING_ISSUE/SUBSCRIPTION_PAUSED keep Pro only until a known future expiry (a refunded lifetime purchase arrives as CANCELLATION with null expiry and must revoke).
export type ProState={isPro:boolean;proExpiresAt:number|null};
const GRANT=['INITIAL_PURCHASE','RENEWAL','UNCANCELLATION','NON_RENEWING_PURCHASE','PRODUCT_CHANGE','SUBSCRIPTION_EXTENDED','TEMPORARY_ENTITLEMENT_GRANT','REFUND_REVERSED'],UNTIL_EXPIRY=['CANCELLATION','BILLING_ISSUE','SUBSCRIPTION_PAUSED'];
export function proFromEvent(e:{type?:unknown;expiration_at_ms?:unknown;grace_period_expiration_at_ms?:unknown},now:number):ProState|null{
 const type=String(e.type),ms=(v:unknown)=>typeof v==='number'&&Number.isFinite(v)?v:null,exp=ms(e.expiration_at_ms),grace=ms(e.grace_period_expiration_at_ms),until=grace!==null&&(exp===null||grace>exp)?grace:exp;
 if(type==='EXPIRATION')return {isPro:false,proExpiresAt:exp};
 if(GRANT.includes(type))return e.expiration_at_ms===null?{isPro:true,proExpiresAt:null}:{isPro:until!==null&&until>now,proExpiresAt:until};
 if(UNTIL_EXPIRY.includes(type))return {isPro:until!==null&&until>now,proExpiresAt:until};
 return null;
}
// Best still-active entitlement among states (lifetime beats any expiry). Used to carry Pro across a RevenueCat TRANSFER.
export function carryPro(states:Array<{isPro?:unknown;proExpiresAt?:number|null}>,now:number):ProState|null{let best:ProState|null=null;for(const s of states){const x=s.proExpiresAt??null;if(s.isPro!==true||(x!==null&&x<=now))continue;if(x===null)return {isPro:true,proExpiresAt:null};if(!best||x>(best.proExpiresAt as number))best={isPro:true,proExpiresAt:x};}return best;}
