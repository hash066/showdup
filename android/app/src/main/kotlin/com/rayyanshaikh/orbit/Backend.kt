package com.rayyanshaikh.orbit
import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.FirebaseOptions
import com.google.firebase.functions.FirebaseFunctions
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.auth.FirebaseAuth
import org.json.JSONObject

object Backend {
 private var configured=false
 fun initialize(c:Context){if(configured)return;val raw=AlarmEngine.prefs(c).getString("backend",null)?:return;val j=JSONObject(raw)
  if(FirebaseApp.getApps(c).isEmpty()){FirebaseApp.initializeApp(c,FirebaseOptions.Builder().setApiKey(j.getString("apiKey")).setApplicationId(j.getString("appId")).setProjectId(j.getString("projectId")).setGcmSenderId(j.getString("senderId")).build())
   if(j.optBoolean("emulators")){val host=j.optString("host","10.0.2.2");FirebaseAuth.getInstance().useEmulator(host,9099);FirebaseFirestore.getInstance().useEmulator(host,8080);FirebaseFunctions.getInstance().useEmulator(host,5001)}
  };configured=true
 }
}
