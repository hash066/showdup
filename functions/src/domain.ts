import {DateTime} from 'luxon';
import {CommitmentSchedule,UserStats,AttemptState} from './types';
export function resolveWindow(s:CommitmentSchedule,date:string){const start=DateTime.fromISO(`${date}T${s.windowStartLocal}`,{zone:s.timezone}),end=DateTime.fromISO(`${date}T${s.windowEndLocal}`,{zone:s.timezone});if(!start.isValid||!end.isValid||end<=start)throw new Error('Invalid window');return {start:start.toMillis(),end:end.toMillis(),weekday:start.weekday};}
export const emptyStats:UserStats={currentStreak:0,longestStreak:0,completed:0,abandoned:0,unverifiable:0};
export function nextStats(current:Partial<UserStats>|undefined,state:AttemptState):UserStats{const s={...emptyStats,...current};if(state==='completed'){s.completed++;s.currentStreak++;s.longestStreak=Math.max(s.longestStreak,s.currentStreak);}if(state==='abandoned'){s.abandoned++;s.currentStreak=0;}if(state==='expired')s.currentStreak=0;if(state==='unverifiable')s.unverifiable++;return s;}
export function evidenceWindow(now:number,start:number,end:number,elapsed:number){return now>=start&&now<=end&&Number.isFinite(elapsed)&&elapsed>=0&&elapsed<=now-start+5000;}
