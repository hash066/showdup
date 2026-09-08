import {z} from 'zod';
import {DateTime} from 'luxon';
import {LocationConfig,StepsConfig,VerifierConfig,VerifierType} from './types';
const n=z.number().finite();
const steps=z.object({targetSteps:n.int().min(200).max(20000),minDurationMs:n.int().min(60000).max(86400000)}).strict();
const location=z.object({lat:n.min(-90).max(90),lng:n.min(-180).max(180),radiusM:n.int().min(100).max(500),dwellMs:n.int().min(60000).max(86400000),label:z.string().max(100).optional()}).strict();
const clock=z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/);
export const scheduleSchema=z.object({daysOfWeek:z.array(n.int().min(1).max(7)).min(1).max(7).refine(a=>new Set(a).size===a.length),windowStartLocal:clock,windowEndLocal:clock,timezone:z.string().refine(s=>DateTime.now().setZone(s).isValid)}).strict().refine(s=>{const m=(v:string)=>+v.slice(0,2)*60 + +v.slice(3);return m(s.windowEndLocal)-m(s.windowStartLocal)>=15;},'Window must last at least 15 minutes and end on the same day.');
export const commitmentSchema=z.object({title:z.string().trim().min(1).max(80),verifierType:z.enum(['steps','location']),verifierConfig:z.unknown(),schedule:scheduleSchema,reminder:z.object({intervalMinutes:n.int().min(5).max(120),volumeMode:z.enum(['gentle','loud']),maxReminders:n.int().min(1).max(20)}).strict(),restrictions:z.object({enabled:z.literal(false),packages:z.array(z.string()).max(0)}).strict()}).strict().superRefine((c,ctx)=>{if(!(c.verifierType==='steps'?steps:location).safeParse(c.verifierConfig).success)ctx.addIssue({code:z.ZodIssueCode.custom,message:'Invalid verifier configuration'});});
export function validateVerifierConfig(type:VerifierType,cfg:unknown):asserts cfg is VerifierConfig{(type==='steps'?steps:location).parse(cfg);}
export function checkStepsPlausibility(a:{stepsSinceBaseline:number;elapsedMs:number;config:StepsConfig}):string|null{
 if(!Number.isSafeInteger(a.stepsSinceBaseline)||!Number.isFinite(a.elapsedMs))return 'Invalid step reading';
 if(a.elapsedMs<Math.max(60000,a.config.minDurationMs))return 'Keep moving a little longer';
 if(a.stepsSinceBaseline<a.config.targetSteps||a.stepsSinceBaseline>50000)return 'Step target not satisfied';
 if(a.stepsSinceBaseline/(a.elapsedMs/60000)>250)return 'Movement rate cannot be verified';return null;
}
export function haversineMetres(a:{lat:number;lng:number},b:{lat:number;lng:number}){const r=(n:number)=>n*Math.PI/180;const h=Math.sin(r(b.lat-a.lat)/2)**2+Math.cos(r(a.lat))*Math.cos(r(b.lat))*Math.sin(r(b.lng-a.lng)/2)**2;return 6371000*2*Math.atan2(Math.sqrt(h),Math.sqrt(Math.max(0,1-h)));}
export function checkLocationPlausibility(a:{lat:number;lng:number;accuracyM:number;isMock:boolean;dwellMs:number;previousFix?:{lat:number;lng:number;epochMs:number};epochMs:number;config:LocationConfig}):string|null{
 if(![a.lat,a.lng,a.accuracyM,a.dwellMs,a.epochMs].every(Number.isFinite)||Math.abs(a.lat)>90||Math.abs(a.lng)>180)return 'Invalid location';
 if(a.isMock!==false)return 'Mock location cannot verify presence';
 if(a.accuracyM<0||a.accuracyM>a.config.radiusM)return 'Location accuracy is too low';
 if(haversineMetres(a,a.config)>a.config.radiusM)return 'Outside the arrival area';
 if(a.dwellMs<a.config.dwellMs)return 'Stay in the arrival area a little longer';
 if(!a.previousFix||![a.previousFix.lat,a.previousFix.lng,a.previousFix.epochMs].every(Number.isFinite))return 'Arrival and dwell require more than one fix';
 const dt=a.epochMs-a.previousFix.epochMs;
 if(dt<=0||haversineMetres(a,a.previousFix)/(dt/1000)*3.6>200)return 'Travel speed cannot be verified';return null;
}
