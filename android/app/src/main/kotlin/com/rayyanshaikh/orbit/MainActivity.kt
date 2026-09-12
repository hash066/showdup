package com.rayyanshaikh.orbit

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.hardware.*
import android.net.Uri
import android.os.*
import android.provider.Settings
import android.provider.AlarmClock
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import com.google.android.gms.location.LocationServices
import com.google.android.libraries.places.api.Places
import com.google.android.libraries.places.api.model.Place
import com.google.android.libraries.places.api.net.FetchPlaceRequest
import com.google.android.libraries.places.widget.PlaceAutocomplete
import com.google.android.libraries.places.widget.PlaceAutocompleteActivity
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.*
import org.json.JSONArray
import org.json.JSONObject

object Events {
 val sinks=mutableMapOf<String,EventChannel.EventSink>()
 fun emit(channel:String,data:Map<String,Any?>){Handler(Looper.getMainLooper()).post{sinks[channel]?.success(data)}}
}
class MainActivity:FlutterFragmentActivity(){
 private var permissionResult:MethodChannel.Result?=null
 private var placeResult:MethodChannel.Result?=null
 private val placeAutocompleteLauncher=registerForActivityResult(ActivityResultContracts.StartActivityForResult()){activityResult->
  val pending=placeResult?:return@registerForActivityResult
  val returned=activityResult.data
  if(activityResult.resultCode!=PlaceAutocompleteActivity.RESULT_OK||returned==null){
   placeResult=null
   if(activityResult.resultCode==PlaceAutocompleteActivity.RESULT_ERROR&&returned!=null)pending.error("place_search_failed",PlaceAutocomplete.getResultStatusFromIntent(returned)?.statusMessage?:"Place search failed.",null)else pending.success(null)
   return@registerForActivityResult
  }
  val data=returned!!
  val prediction=PlaceAutocomplete.getPredictionFromIntent(data)
  if(prediction==null){placeResult=null;pending.error("place_search_failed","No place was selected.",null);return@registerForActivityResult}
  val token=PlaceAutocomplete.getSessionTokenFromIntent(data)
  val fields=listOf(Place.Field.ID,Place.Field.FORMATTED_ADDRESS,Place.Field.LOCATION)
  val request=FetchPlaceRequest.builder(prediction.placeId,fields).setSessionToken(token).build()
  Places.createClient(this).fetchPlace(request).addOnSuccessListener{response->
   val place=response.place;val point=place.location
   placeResult=null
   if(point==null)pending.error("place_has_no_location","That result has no map location. Choose another gym.",null)
   else pending.success(mapOf("id" to (place.id?:prediction.placeId),"name" to prediction.getPrimaryText(null).toString(),"address" to (place.formattedAddress?:prediction.getFullText(null).toString()),"lat" to point.latitude,"lng" to point.longitude))
  }.addOnFailureListener{error->placeResult=null;pending.error("place_details_failed",error.message?:"Could not load that place.",null)}
 }
 override fun onNewIntent(newIntent: Intent) {
  super.onNewIntent(newIntent)
  setIntent(newIntent)
 }
 override fun configureFlutterEngine(engine:FlutterEngine){
  super.configureFlutterEngine(engine)
  for(name in listOf("alarm","steps","location")){
   EventChannel(engine.dartExecutor.binaryMessenger,"app.showdup/${name}_events").setStreamHandler(object:EventChannel.StreamHandler{
    override fun onListen(args:Any?,sink:EventChannel.EventSink){Events.sinks[name]=sink}
    override fun onCancel(args:Any?){Events.sinks.remove(name)}
   })
   MethodChannel(engine.dartExecutor.binaryMessenger,"app.showdup/$name").setMethodCallHandler{call,result->
    try{when(name){"alarm"->alarm(call,result);"steps"->steps(call,result);else->location(call,result)}}catch(e:Exception){result.error("native_error",e.message,null)}
   }
  }
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.showdup/blocker").setMethodCallHandler{call,result->try{when(call.method){
   "getStatus","status"->result.success(AppBlocker.status(this))
   "listApps"->result.success(AppBlocker.launchableApps(this))
   "openAccessibilitySettings"-> { AppBlocker.openAccessibilitySettings(this); result.success(true) }
   "configure"->{val a=call.arguments as? Map<*,*>?:emptyMap<String,Any>();val packages=(a["packages"] as? List<*>)?.mapNotNull{it?.toString()}?:emptyList();result.success(AppBlocker.configure(this,packages,(a["activeUntilEpochMs"] as? Number)?.toLong()?:0,a["commitmentId"]?.toString(),a["attemptId"]?.toString(),(a["activeFromEpochMs"] as? Number)?.toLong()?:System.currentTimeMillis()))}
   "sync"->{val a=call.arguments as? Map<*,*>?:emptyMap<String,Any>();val sessions=(a["sessions"] as? List<*>)?.mapNotNull{it as? Map<*,*>}?:emptyList();result.success(AppBlocker.sync(this,sessions))}
   "setEntitlement"->{val a=call.arguments as? Map<*,*>?:emptyMap<String,Any>();AppBlocker.setEntitlement(this,a["enabled"]==true,(a["expiresAtEpochMs"] as? Number)?.toLong());result.success(true)}
   "stop"->{val a=call.arguments as? Map<*,*>;AppBlocker.stop(this,a?.get("attemptId")?.toString());result.success(true)}
   else->result.notImplemented()
  }}catch(e:Exception){result.error("blocker_error",e.message,null)}}
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.showdup/overlay").setMethodCallHandler{call,result->try{when(call.method){
   "status"->result.success(OverlayService.status(this))
   "requestPermission"->{startActivity(OverlayService.permissionIntent(this));result.success(true)}
   "enable"->result.success(OverlayService.enable(this))
   "disable"->{OverlayService.disable(this);result.success(true)}
   "syncSnapshot"->{OverlayService.sync(this,call.arguments as? Map<*,*>?:emptyMap<String,Any>());result.success(true)}
   else->result.notImplemented()
  }}catch(e:Exception){result.error("overlay_error",e.message,null)}}
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.showdup/social").setMethodCallHandler{call,result->try{when(call.method){
   "getLaunchInvite"->{val code=intent.data?.takeIf{it.host=="showdup-f0799.web.app"&&it.pathSegments.firstOrNull()=="i"}?.lastPathSegment;intent.data=null;result.success(code)}
   else->result.notImplemented()
  }}catch(e:Exception){result.error("social_error",e.message,null)}}
  MethodChannel(engine.dartExecutor.binaryMessenger,"app.showdup/places").setMethodCallHandler{call,result->try{when(call.method){
   "pickPlace"->{
    if(placeResult!=null){result.error("busy","Place search is already open.",null);return@setMethodCallHandler}
    val key=BuildConfig.PLACES_API_KEY
    if(key.isBlank()||key=="DEFAULT_API_KEY"){result.error("maps_not_configured","Gym search needs an Android-restricted Places API key in android/secrets.properties.",null);return@setMethodCallHandler}
    if(!Places.isInitialized())Places.initializeWithNewPlacesApiEnabled(applicationContext,key)
    placeResult=result
    val initial=(call.arguments as? Map<*,*>)?.get("initialQuery")?.toString().orEmpty()
    placeAutocompleteLauncher.launch(PlaceAutocomplete.createIntent(this){if(initial.isNotBlank())setInitialQuery(initial)})
   }
   else->result.notImplemented()
  }}catch(e:Exception){placeResult=null;result.error("places_error",e.message,null)}}
  AlarmEngine.channels(this)
  if(intent.getBooleanExtra("restoreOverlay",false)){intent.removeExtra("restoreOverlay");OverlayService.enable(this)}
 }
 private fun granted(p:String)=ContextCompat.checkSelfPermission(this,p)==PackageManager.PERMISSION_GRANTED
 private fun alarm(c:MethodCall,r:MethodChannel.Result){val args=c.arguments as? Map<*,*>?:emptyMap<String,Any>()
  when(c.method){
   // Compatibility no-op while the app transitions to local-first storage.
   "configureBackend"->{r.success(true)}
   "pendingCompletions"->{
    val completions=mutableMapOf<String,Any?>()
    for((key,value) in AlarmEngine.prefs(this).all)if(key.startsWith("completion:"))try{
     completions[key.removePrefix("completion:")]=JSONObject(value as String).toMap()
    }catch(_:Exception){}
    r.success(completions)
   }
   "acknowledgeCompletions"->{
    val ids=args["attemptIds"] as? List<*>?:emptyList<Any>()
    val edit=AlarmEngine.prefs(this).edit()
    ids.forEach{edit.remove("completion:$it")}
    edit.apply();r.success(true)
   }
   "pendingFailures"->{
    val failures=mutableMapOf<String,Any?>()
    for((key,value) in AlarmEngine.prefs(this).all)if(key.startsWith("failure:"))try{
     failures[key.removePrefix("failure:")]=JSONObject(value as String).toMap()
    }catch(_:Exception){}
    r.success(failures)
   }
   "acknowledgeFailures"->{
    val ids=args["attemptIds"] as? List<*>?:emptyList<Any>()
    val edit=AlarmEngine.prefs(this).edit()
    ids.forEach{edit.remove("failure:$it")}
    edit.apply();r.success(true)
   }
   "pendingExpirations"->{
    val expirations=mutableMapOf<String,Any?>()
    for((key,value) in AlarmEngine.prefs(this).all)if(key.startsWith("expiration:"))try{expirations[key.removePrefix("expiration:")]=JSONObject(value as String).toMap()}catch(_:Exception){}
    r.success(expirations)
   }
   "acknowledgeExpirations"->{val ids=args["attemptIds"] as? List<*>?:emptyList<Any>();val edit=AlarmEngine.prefs(this).edit();ids.forEach{edit.remove("expiration:$it")};edit.apply();r.success(true)}
   "pendingReminderEvents"->{
    val events=mutableMapOf<String,Any?>();val counts=mutableMapOf<String,Int>()
    for((key,value) in AlarmEngine.prefs(this).all)try{when{
     key.startsWith("reminder_event:")->events[key.removePrefix("reminder_event:")]=JSONObject(value as String).toMap()
     key.startsWith("reminder_count:")->counts[key.removePrefix("reminder_count:")]=value as Int
    }}catch(_:Exception){}
    r.success(mapOf("events" to events,"counts" to counts))
   }
   "acknowledgeReminderEvents"->{val ids=args["eventIds"] as? List<*>?:emptyList<Any>();val edit=AlarmEngine.prefs(this).edit();ids.forEach{edit.remove("reminder_event:$it")};edit.apply();r.success(true)}
   "scheduleReminders"->{r.success(AlarmEngine.schedule(this,JSONObject(args)))}
   "cancelReminders"->{AlarmEngine.cancel(this,args["attemptId"].toString());r.success(true)}
   "configureCommitments"->{AlarmEngine.configure(this,args["commitments"] as? List<*>?:emptyList<Any>());r.success(true)}
   "createNativeAlarm"->{
    val days=(args["days"] as? List<*>)?.mapNotNull{(it as? Number)?.toInt()}?:emptyList()
    val intent=Intent(AlarmClock.ACTION_SET_ALARM).apply{
     putExtra(AlarmClock.EXTRA_HOUR,(args["hour"] as Number).toInt())
     putExtra(AlarmClock.EXTRA_MINUTES,(args["minute"] as Number).toInt())
     putExtra(AlarmClock.EXTRA_MESSAGE,args["label"]?.toString()?:"ShowdUp alarm")
     putExtra(AlarmClock.EXTRA_SKIP_UI,false)
     if(days.isNotEmpty())putExtra(AlarmClock.EXTRA_DAYS,ArrayList(days.map{when(it){1->java.util.Calendar.MONDAY;2->java.util.Calendar.TUESDAY;3->java.util.Calendar.WEDNESDAY;4->java.util.Calendar.THURSDAY;5->java.util.Calendar.FRIDAY;6->java.util.Calendar.SATURDAY;else->java.util.Calendar.SUNDAY}}))
    }
    if(intent.resolveActivity(packageManager)==null)r.error("clock_missing","No alarm clock app can handle this request.",null)else{startActivity(intent);r.success(true)}
   }
   "showNativeAlarms"->{val i=Intent(AlarmClock.ACTION_SHOW_ALARMS);if(i.resolveActivity(packageManager)==null)r.error("clock_missing","No alarm clock app is available.",null)else{startActivity(i);r.success(true)}}
   "silence"->{AlarmEngine.silence(this,args["attemptId"].toString(),true,"manual");r.success(true)}
   "getLaunchAttempt"->{val launchAttempt=intent.getStringExtra("attemptId")?:intent.data?.getQueryParameter("attemptId");intent.removeExtra("attemptId");intent.data=null;r.success(launchAttempt)}
   "getPermissionStatus"->{val am=getSystemService(AlarmManager::class.java);r.success(mapOf("exactAlarm" to (Build.VERSION.SDK_INT<31||am.canScheduleExactAlarms()),"notifications" to (Build.VERSION.SDK_INT<33||granted(Manifest.permission.POST_NOTIFICATIONS)),"batteryOptimised" to !getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),"fullScreenIntent" to (Build.VERSION.SDK_INT<34||getSystemService(NotificationManager::class.java).canUseFullScreenIntent()),"activityRecognition" to (Build.VERSION.SDK_INT<29||granted(Manifest.permission.ACTIVITY_RECOGNITION)),"location" to granted(Manifest.permission.ACCESS_FINE_LOCATION),"manufacturer" to Build.MANUFACTURER))}
   "requestPermission"->{val which=args["which"].toString();val perms=when(which){"notifications"->if(Build.VERSION.SDK_INT>=33)arrayOf(Manifest.permission.POST_NOTIFICATIONS)else emptyArray();"activityRecognition"->if(Build.VERSION.SDK_INT>=29)arrayOf(Manifest.permission.ACTIVITY_RECOGNITION)else emptyArray();"location"->arrayOf(Manifest.permission.ACCESS_FINE_LOCATION,Manifest.permission.ACCESS_COARSE_LOCATION);else->emptyArray()}
    if(perms.isNotEmpty()){if(permissionResult!=null){r.error("busy","A permission request is already open",null);return};permissionResult=r;requestPermissions(perms,701);return}
    val settings=when(which){"exactAlarm"->if(Build.VERSION.SDK_INT>=31)Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM else null;"battery"->Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS;"fullScreenIntent"->if(Build.VERSION.SDK_INT>=34)Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT else null;"autostart"->null;else->Settings.ACTION_APPLICATION_DETAILS_SETTINGS}
    if(which=="autostart")openAutostart() else if(settings!=null)startActivity(Intent(settings).apply{if(which!="battery")data=Uri.parse("package:$packageName")});r.success(true)
   }
   "stopAll"->{AlarmEngine.clear(this);stopService(Intent(this,TrackingService::class.java));r.success(true)}
   else->r.notImplemented()
  }
 }
 private fun steps(c:MethodCall,r:MethodChannel.Result){when(c.method){
  "getStepCount"->{val sm=getSystemService(SensorManager::class.java);val sensor=sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER);if(sensor==null){r.success(mapOf("available" to false));return}
   if(Build.VERSION.SDK_INT>=29&&!granted(Manifest.permission.ACTIVITY_RECOGNITION)){r.error("permission_denied","Allow physical activity to count steps",null);return}
   var done=false;val handler=Handler(Looper.getMainLooper());lateinit var listener:SensorEventListener
   listener=object:SensorEventListener{override fun onAccuracyChanged(s:Sensor?,a:Int){};override fun onSensorChanged(e:SensorEvent){if(done)return;done=true;sm.unregisterListener(this);r.success(mapOf("available" to true,"cumulativeSteps" to e.values[0].toLong(),"sensorBootTime" to bootId()))}}
   sm.registerListener(listener,sensor,SensorManager.SENSOR_DELAY_NORMAL);handler.postDelayed({if(!done){done=true;sm.unregisterListener(listener);r.error("sensor_wait","Move a few steps, then try again",null)}},10000)
  }
  "startTracking"->{val data=JSONObject(c.arguments as Map<*,*>);r.success(TrackingService.start(this,"steps",data))}
  "stopTracking"->{TrackingService.stop(this,c.argument<String>("attemptId")!!);r.success(true)}
  else->r.notImplemented()
 }}
 private fun location(c:MethodCall,r:MethodChannel.Result){when(c.method){
  "startWatch"->{r.success(TrackingService.start(this,"location",JSONObject(c.arguments as Map<*,*>)))}
  "startWalk"->{r.success(TrackingService.start(this,"walk",JSONObject(c.arguments as Map<*,*>)))}
  "stopWatch"->{TrackingService.stop(this,c.argument<String>("attemptId")!!);r.success(true)}
  "isWatching"->r.success(TrackingService.hasLocation)
  "currentLocation"->{if(!granted(Manifest.permission.ACCESS_FINE_LOCATION)){r.error("permission_denied","Allow precise location first",null);return};LocationServices.getFusedLocationProviderClient(this).getCurrentLocation(com.google.android.gms.location.Priority.PRIORITY_HIGH_ACCURACY,null).addOnSuccessListener{l->if(l==null)r.error("unavailable","No location fix. Try outdoors.",null)else r.success(mapOf("lat" to l.latitude,"lng" to l.longitude))}.addOnFailureListener{r.error("unavailable",it.message,null)}}
  else->r.notImplemented()
 }}
 override fun onRequestPermissionsResult(code:Int,permissions:Array<out String>,results:IntArray){super.onRequestPermissionsResult(code,permissions,results);if(code==701){permissionResult?.success(results.isNotEmpty()&&results.all{it==PackageManager.PERMISSION_GRANTED});permissionResult=null}}
 private fun openAutostart(){val candidates=listOf(ComponentName("com.miui.securitycenter","com.miui.permcenter.autostart.AutoStartManagementActivity"),ComponentName("com.coloros.safecenter","com.coloros.safecenter.permission.startup.StartupAppListActivity"),ComponentName("com.vivo.permissionmanager","com.vivo.permissionmanager.activity.BgStartUpManagerActivity"));for(c in candidates){try{startActivity(Intent().setComponent(c));return}catch(_:Exception){}};startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,Uri.parse("package:$packageName")))}
}
private fun JSONObject.toMap(): Map<String, Any?> {
 val result=mutableMapOf<String,Any?>()
 val iterator=keys()
 while(iterator.hasNext()){
  val key=iterator.next()
  result[key]=when(val value=get(key)){
   is JSONObject->value.toMap()
   is JSONArray->value.toList()
   JSONObject.NULL->null
   else->value
  }
 }
 return result
}
private fun JSONArray.toList(): List<Any?> {
 return (0 until length()).map { index ->
  when(val value=get(index)){
   is JSONObject->value.toMap()
   is JSONArray->value.toList()
   JSONObject.NULL->null
   else->value
  }
 }
}
fun bootId():Long=(System.currentTimeMillis()-SystemClock.elapsedRealtime())/10000
