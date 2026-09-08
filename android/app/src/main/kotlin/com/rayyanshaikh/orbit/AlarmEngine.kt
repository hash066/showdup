package com.rayyanshaikh.orbit

import android.app.*
import android.content.*
import android.media.*
import android.os.*
import androidx.core.app.NotificationCompat
import com.google.firebase.functions.FirebaseFunctions
import org.json.*
import java.time.*

object AlarmEngine {
 private var ringtone:Ringtone?=null
 private var originalVolume:Int?=null
 private var ringingId:String?=null
 private val handler=Handler(Looper.getMainLooper())
 fun prefs(c:Context)=c.getSharedPreferences("showdup_native",Context.MODE_PRIVATE)
 fun channels(c:Context){val nm=c.getSystemService(NotificationManager::class.java);nm.createNotificationChannel(NotificationChannel("reminders","Commitment reminders",NotificationManager.IMPORTANCE_HIGH).apply{description="Reminders until verified or your window ends";setSound(null,null)});nm.createNotificationChannel(NotificationChannel("tracking","Verification in progress",NotificationManager.IMPORTANCE_LOW));}
 fun launch(c:Context,id:String)=PendingIntent.getActivity(c,id.hashCode(),Intent(c,MainActivity::class.java).putExtra("attemptId",id).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 private fun alarmIntent(c:Context,id:String,index:Int)=PendingIntent.getBroadcast(c,("$id:$index").hashCode(),Intent(c,AlarmReceiver::class.java).setAction("showdup.reminder.$id.$index").putExtra("attemptId",id).putExtra("index",index),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
 fun schedule(c:Context,j:JSONObject):Boolean{
  val id=j.getString("attemptId");if(prefs(c).getBoolean("ended:$id",false))return true
  prefs(c).edit().putString("alarm:$id",j.toString()).apply();val am=c.getSystemService(AlarmManager::class.java)
  val exact=Build.VERSION.SDK_INT<31||am.canScheduleExactAlarms()
  for(i in 0 until j.getInt("maxReminders")){val at=j.getLong("startEpochMs")+i*j.getLong("intervalMinutes")*60000;if(at>=j.getLong("endEpochMs")||at<System.currentTimeMillis())continue;val pi=alarmIntent(c,id,i);if(exact)am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pi)else am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pi)}
  return exact
 }
 fun cancel(c:Context,id:String){val s=prefs(c).getString("alarm:$id",null);if(s!=null){val j=JSONObject(s);for(i in 0 until j.getInt("maxReminders"))c.getSystemService(AlarmManager::class.java).cancel(alarmIntent(c,id,i))};prefs(c).edit().remove("alarm:$id").putBoolean("ended:$id",true).apply();silence(c,id,false)}
 fun silence(c:Context,id:String,snooze:Boolean){if(ringingId==id){ringtone?.stop();ringtone=null;ringingId=null;originalVolume?.let{c.getSystemService(AudioManager::class.java).setStreamVolume(AudioManager.STREAM_ALARM,it,0)};originalVolume=null};c.getSystemService(NotificationManager::class.java).cancel(id.hashCode());if(snooze)event(c,id,"snoozed",System.currentTimeMillis().toString())}
 fun event(c:Context,id:String,type:String,index:String){val eventId="$type:$index";val data=mapOf("attemptId" to id,"type" to type,"eventId" to eventId);prefs(c).edit().putString("event:$id:$eventId",JSONObject(data).toString()).apply();Events.emit("alarm",mapOf("attemptId" to id,"type" to type,"index" to (index.toIntOrNull()?:0)));flushEvents(c)}
 fun flushEvents(c:Context){try{for((k,v)in prefs(c).all){if(!k.startsWith("event:"))continue;val j=JSONObject(v as String);FirebaseFunctions.getInstance().getHttpsCallable("recordReminderEvent").call(mapOf("attemptId" to j.getString("attemptId"),"type" to j.getString("type"),"eventId" to j.getString("eventId"))).addOnSuccessListener{prefs(c).edit().remove(k).apply()}}}catch(_:Exception){}}
 fun fire(c:Context,id:String,index:Int){val raw=prefs(c).getString("alarm:$id",null)?:return;val j=JSONObject(raw);if(System.currentTimeMillis()>j.getLong("endEpochMs")||prefs(c).getBoolean("ended:$id",false))return;channels(c)
  val snooze=PendingIntent.getBroadcast(c,("snooze:$id").hashCode(),Intent(c,AlarmReceiver::class.java).setAction("showdup.snooze").putExtra("attemptId",id),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  val n=NotificationCompat.Builder(c,"reminders").setSmallIcon(R.drawable.ic_notification).setContentTitle(j.optString("title","Time to show up")).setContentText("Snooze buys time. Only evidence completes it.").setPriority(NotificationCompat.PRIORITY_MAX).setCategory(NotificationCompat.CATEGORY_ALARM).setContentIntent(launch(c,id)).setFullScreenIntent(launch(c,id),true).setAutoCancel(true).addAction(0,"Snooze",snooze).build()
  c.getSystemService(NotificationManager::class.java).notify(id.hashCode(),n)
  ringingId?.let{silence(c,it,false)};ringingId=id
  if(j.optString("volumeMode")=="loud"){val audio=c.getSystemService(AudioManager::class.java);originalVolume=audio.getStreamVolume(AudioManager.STREAM_ALARM);audio.setStreamVolume(AudioManager.STREAM_ALARM,audio.getStreamMaxVolume(AudioManager.STREAM_ALARM),0)}
  ringtone=RingtoneManager.getRingtone(c,RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM));ringtone?.audioAttributes=AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build();ringtone?.play();handler.postDelayed({if(ringingId==id)silence(c,id,false)},30000)
  event(c,id,"fired",index.toString())
  if(j.optString("verifierType")=="steps")try{val cfg=j.getJSONObject("verifierConfig");TrackingService.start(c,"steps",JSONObject().put("attemptId",id).put("targetSteps",cfg.getInt("targetSteps")).put("minDurationMs",cfg.getLong("minDurationMs")).put("untilEpochMs",j.getLong("endEpochMs")))}catch(_:Exception){}
  restore(c)
 }
 fun configure(c:Context,commitments:List<*>){val list=JSONArray(commitments);prefs(c).edit().putString("commitments",list.toString()).apply();val activeIds=(0 until list.length()).map{list.getJSONObject(it).getString("id")}.toSet();for((k,_)in prefs(c).all){if(k.startsWith("alarm:")){val aid=k.removePrefix("alarm:");if(aid.substringBeforeLast('_') !in activeIds)cancel(c,aid)}};restore(c)}
 fun restore(c:Context){
  val list=JSONArray(prefs(c).getString("commitments","[]"));val now=System.currentTimeMillis()
  for(i in 0 until list.length()){val commitment=list.getJSONObject(i),s=commitment.getJSONObject("schedule"),r=commitment.getJSONObject("reminder");val zone=ZoneId.of(s.getString("timezone"));val today=Instant.ofEpochMilli(now).atZone(zone).toLocalDate();val days=s.getJSONArray("daysOfWeek");for(d in 0..8){val date=today.plusDays(d.toLong());if((0 until days.length()).none{days.getInt(it)==date.dayOfWeek.value})continue;val start=date.atTime(LocalTime.parse(s.getString("windowStartLocal"))).atZone(zone).toInstant().toEpochMilli();val end=date.atTime(LocalTime.parse(s.getString("windowEndLocal"))).atZone(zone).toInstant().toEpochMilli();if(end<=now)continue;val id="${commitment.getString("id")}_$date";schedule(c,JSONObject().put("attemptId",id).put("startEpochMs",start).put("endEpochMs",end).put("intervalMinutes",r.getInt("intervalMinutes")).put("maxReminders",r.getInt("maxReminders")).put("volumeMode",r.getString("volumeMode")).put("title",commitment.getString("title")).put("verifierType",commitment.getString("verifierType")).put("verifierConfig",commitment.getJSONObject("verifierConfig")))}}
  // Daily maintenance replenishes future reminders even if the app stays closed.
  val pi=PendingIntent.getBroadcast(c,814,Intent(c,BootReceiver::class.java).setAction("showdup.maintenance"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE);c.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,now+86400000,pi)
  for((k,v) in prefs(c).all){if(k.startsWith("alarm:")){val j=JSONObject(v as String);if(j.getLong("endEpochMs")<now){prefs(c).edit().remove(k).apply();silence(c,k.removePrefix("alarm:"),false)}}}
 }
 fun clear(c:Context){for((k,_)in prefs(c).all)if(k.startsWith("alarm:"))cancel(c,k.removePrefix("alarm:"));prefs(c).edit().clear().apply()}
}
class AlarmReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){val id=i.getStringExtra("attemptId")?:return;if(i.action=="showdup.snooze")AlarmEngine.silence(c,id,true)else AlarmEngine.fire(c,id,i.getIntExtra("index",0))}}
class BootReceiver:BroadcastReceiver(){override fun onReceive(c:Context,i:Intent){AlarmEngine.restore(c);/* Location requires a visible activity; notification invites the user back. */}}
