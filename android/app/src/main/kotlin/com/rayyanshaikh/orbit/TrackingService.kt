package com.rayyanshaikh.orbit

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.ServiceInfo
import android.hardware.*
import android.location.Location
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*
import org.json.*

class TrackingService:Service(),SensorEventListener{
 companion object{
  var hasLocation=false
  fun start(c:Context,type:String,data:JSONObject):Boolean=try{ContextCompat.startForegroundService(c,Intent(c,TrackingService::class.java).setAction("start").putExtra("type",type).putExtra("data",data.toString()));true}catch(e:Exception){Log.e("ShowdUpTracking","Foreground verification service start denied for $type",e);AlarmEngine.diagnostic(c,"tracking_start",e.message?:"Android denied starting verification.");false}
  fun stop(c:Context,id:String){c.startService(Intent(c,TrackingService::class.java).setAction("stop").putExtra("attemptId",id))}
 }
 private val tracks=mutableMapOf<String,JSONObject>()
 private val handler=Handler(Looper.getMainLooper())
 private lateinit var sensors:SensorManager
 private lateinit var fused:FusedLocationProviderClient
 private var locationRegistered=false
 private var stepsRegistered=false
 private val callback=object:LocationCallback(){override fun onLocationResult(result:LocationResult){for(l in result.locations)onLocation(l)}}
 private val ticker=object:Runnable{override fun run(){for((id,j)in tracks.toMap()){
  if(System.currentTimeMillis()>j.optLong("untilEpochMs",0)){remove(id);continue}
  if(j.optString("type")=="steps"&&j.has("baseline"))stepProgress(id,j)
 };if(tracks.isNotEmpty())handler.postDelayed(this,5000)}}
 override fun onCreate(){super.onCreate();sensors=getSystemService(SensorManager::class.java);fused=LocationServices.getFusedLocationProviderClient(this);AlarmEngine.channels(this)}
 override fun onBind(i:Intent?):IBinder?=null
 override fun onStartCommand(i:Intent?,flags:Int,startId:Int):Int{
  if(i?.action=="stop"){remove(i.getStringExtra("attemptId")?:"");return START_NOT_STICKY}
  if(i==null){for((k,v)in AlarmEngine.prefs(this).all)if(k.startsWith("track:")){val j=JSONObject(v as String);if(j.optLong("untilEpochMs")>System.currentTimeMillis())tracks[k.removePrefix("track:")]=j}}
  else{
   val input=JSONObject(i.getStringExtra("data")?:"{}")
   val id=input.getString("attemptId")
   val type=i.getStringExtra("type")?:"steps"
   val old=AlarmEngine.prefs(this).getString("track:$id",null)
   val j=if(old!=null) JSONObject(old) else input
   j.put("type",type)
   val alarm=AlarmEngine.prefs(this).getString("alarm:$id",null)?.let{JSONObject(it)}
   if(!j.has("untilEpochMs"))j.put("untilEpochMs",alarm?.optLong("endEpochMs")?:System.currentTimeMillis()+7200000)
   if(!j.has("minDurationMs"))j.put("minDurationMs",alarm?.optJSONObject("verifierConfig")?.optLong("minDurationMs")?:60000)
   if(!j.has("startedAt"))j.put("startedAt",System.currentTimeMillis())
   if(!j.has("startedElapsed"))j.put("startedElapsed",SystemClock.elapsedRealtime())
   tracks[id]=j
  }
  if(tracks.isEmpty()){stopSelf();return START_NOT_STICKY}
  hasLocation=tracks.values.any{it.optString("type")=="location"}
  val notification=NotificationCompat.Builder(this,"tracking").setSmallIcon(R.drawable.ic_notification).setContentTitle("Showing up, one step at a time").setContentText("Verification is active. Tap to see progress or end today.").setOngoing(true).setContentIntent(AlarmEngine.launch(this,tracks.keys.first())).build()
  try{if(Build.VERSION.SDK_INT>=29){var type=0;if(hasLocation)type=type or ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION;if(tracks.values.any{it.optString("type")=="steps"}&&Build.VERSION.SDK_INT>=34)type=type or ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH;startForeground(910,notification,type)}else startForeground(910,notification)}catch(e:Exception){Log.e("ShowdUpTracking","Unable to enter foreground for verification",e);AlarmEngine.diagnostic(this,"tracking_foreground",e.message?:"Android denied verification foreground service.");for((id,j)in tracks.toMap())fail(id,j,"permission_denied");stopSelf();return START_NOT_STICKY}
  try{
   if(!stepsRegistered&&tracks.values.any{it.optString("type")=="steps"}){val sensor=sensors.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);if(sensor==null){for((id,j)in tracks.toMap())if(j.optString("type")=="steps")fail(id,j,"sensor_missing")}else stepsRegistered=sensors.registerListener(this,sensor,SensorManager.SENSOR_DELAY_NORMAL)}
   if(hasLocation&&!locationRegistered){fused.requestLocationUpdates(LocationRequest.Builder(Priority.PRIORITY_BALANCED_POWER_ACCURACY,60000).setMinUpdateIntervalMillis(30000).build(),callback,Looper.getMainLooper());locationRegistered=true}
  }catch(e:SecurityException){Log.e("ShowdUpTracking","Verification permission missing",e);AlarmEngine.diagnostic(this,"tracking_permission",e.message?:"Verification permission missing.");for((id,j)in tracks.toMap())fail(id,j,"permission_denied")}
  for((id,j)in tracks)persist(id,j)
  handler.removeCallbacks(ticker);handler.post(ticker);return START_STICKY
 }
 private fun persist(id:String,j:JSONObject){AlarmEngine.prefs(this).edit().putString("track:$id",j.toString()).apply()}
 override fun onAccuracyChanged(s:Sensor?,a:Int){}
  override fun onSensorChanged(e:SensorEvent){
   val count=e.values[0].toLong()
   val boot=bootId()
   for((id,j)in tracks.toMap()) if(j.optString("type")=="steps"){
  if(!j.has("baseline")){j.put("baseline",count);j.put("boot",boot);j.put("credited",0);j.put("last",count)}
  else if(kotlin.math.abs(j.optLong("boot")-boot)>2||count<j.optLong("last")){j.put("credited",j.optLong("credited")+(j.optLong("last")-j.optLong("baseline")).coerceAtLeast(0));j.put("baseline",count);j.put("boot",boot)}
  j.put("last",count);persist(id,j);stepProgress(id,j)
   }
  }
 private fun stepProgress(id:String,j:JSONObject){val total=j.optLong("credited")+(j.optLong("last")-j.optLong("baseline")).coerceAtLeast(0);val elapsed=System.currentTimeMillis()-j.getLong("startedAt");val target=j.getInt("targetSteps");val ready=total>=target&&elapsed>=j.optLong("minDurationMs",60000)&&total/(elapsed/60000.0)<=250
  Events.emit("steps",mapOf("type" to if(ready)"target_reached" else "progress","attemptId" to id,"stepsSinceBaseline" to total,"elapsedMs" to elapsed))
  if(ready)submit(id,"steps",mapOf("stepsSinceBaseline" to total,"elapsedMs" to elapsed,"baselineCapturedAt" to j.getLong("startedAt")))
 }
 private fun onLocation(l:Location){for((id,j)in tracks.toMap())if(j.optString("type")=="location"){
  val distance=FloatArray(1);Location.distanceBetween(l.latitude,l.longitude,j.getDouble("lat"),j.getDouble("lng"),distance)
  val mock=if(Build.VERSION.SDK_INT>=31)l.isMock else l.isFromMockProvider
  val valid=!mock&&l.hasAccuracy()&&l.accuracy<=j.getInt("radiusM")&&distance[0]<=j.getInt("radiusM")
  val previous=j.optJSONObject("previousFix");val epoch=l.time;val stale=System.currentTimeMillis()-epoch>120000
  if(!valid||stale||previous!=null&&(epoch-previous.getLong("epochMs")>120000||epoch<=previous.getLong("epochMs"))){j.remove("enteredAt");j.remove("enteredElapsed")}
  if(valid&&!stale&&!j.has("enteredAt")){j.put("enteredAt",epoch);j.put("enteredElapsed",l.elapsedRealtimeNanos/1000000)}
  val dwell=if(valid&&!stale) (l.elapsedRealtimeNanos/1000000-j.optLong("enteredElapsed",l.elapsedRealtimeNanos/1000000)).coerceAtLeast(0) else 0
  val fix=mapOf("lat" to l.latitude,"lng" to l.longitude,"accuracyM" to l.accuracy.toDouble(),"isMock" to mock,"epochMs" to epoch)
  val ready=valid&&!stale&&dwell>=j.getLong("dwellMs")&&previous!=null
  Events.emit("location",mapOf("type" to if(ready)"dwell_satisfied"else"dwell_progress","attemptId" to id,"distanceM" to distance[0].toDouble(),"dwellMs" to dwell,"fix" to fix))
  if(ready){
   submit(id,"location",fix+mapOf("dwellMs" to dwell,"enteredAt" to j.getLong("enteredAt"),"previousFix" to mapOf("lat" to previous!!.getDouble("lat"),"lng" to previous.getDouble("lng"),"epochMs" to previous.getLong("epochMs"))))
   continue
  }
  j.put("previousFix",JSONObject(fix));persist(id,j)
 }}
 /** Completion is local and immediate. The event reaches Flutter when it is alive;
  * a durable record lets local storage reconcile after a process restart. */
 private fun submit(id:String,type:String,payload:Map<String,Any>){AlarmEngine.prefs(this).edit().putString("completion:$id",JSONObject().put("type",type).put("payload",JSONObject(payload)).put("completedAt",System.currentTimeMillis()).toString()).apply();AlarmEngine.cancel(this,id);remove(id)}
 private fun fail(id:String,j:JSONObject,reason:String){AlarmEngine.prefs(this).edit().putString("failure:$id",JSONObject().put("type",j.optString("type")).put("reason",reason).put("failedAt",System.currentTimeMillis()).toString()).apply();Events.emit(j.optString("type"),mapOf("type" to if(j.optString("type")=="steps")"sensor_lost"else"unavailable","attemptId" to id,"reason" to reason));AlarmEngine.cancel(this,id);remove(id)}
 private fun remove(id:String){tracks.remove(id);AlarmEngine.prefs(this).edit().remove("track:$id").apply();hasLocation=tracks.values.any{it.optString("type")=="location"};if(!hasLocation&&locationRegistered){fused.removeLocationUpdates(callback);locationRegistered=false};if(tracks.isEmpty()){stopForeground(STOP_FOREGROUND_REMOVE);stopSelf()}}
 override fun onDestroy(){sensors.unregisterListener(this);fused.removeLocationUpdates(callback);handler.removeCallbacksAndMessages(null);hasLocation=false;super.onDestroy()}
}
