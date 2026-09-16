package com.rayyanshaikh.orbit

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import java.time.Instant
import kotlin.math.max
import kotlin.math.min

object HealthConnectBridge {
    val exercisePermission = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
    const val backgroundPermission = "android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND"
    val permissions = setOf(exercisePermission, backgroundPermission)

    fun sdkAvailable(context: Context): Boolean =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    suspend fun availability(context: Context): Map<String, Any?> {
        if (!sdkAvailable(context)) return mapOf(
            "available" to false,
            "permissionsGranted" to false,
            "reason" to "Health Connect is unavailable or needs an update.",
        )
        val granted = HealthConnectClient.getOrCreate(context)
            .permissionController.getGrantedPermissions()
        return mapOf(
            "available" to true,
            "permissionsGranted" to granted.containsAll(permissions),
            "reason" to if (granted.containsAll(permissions)) null else
                "Allow exercise sessions and background health access in Health Connect.",
        )
    }

    suspend fun checkWorkout(context: Context, args: Map<*, *>): Map<String, Any?> {
        if (!sdkAvailable(context)) return mapOf("satisfied" to false, "progress" to 0.0, "unavailable" to true)
        val startMs = (args["startEpochMs"] as? Number)?.toLong() ?: return emptyMap()
        val endMs = (args["endEpochMs"] as? Number)?.toLong() ?: return emptyMap()
        val targetMs = (args["targetDurationMs"] as? Number)?.toLong() ?: return emptyMap()
        val activity = args["activityType"]?.toString() ?: "any"
        val client = HealthConnectClient.getOrCreate(context)
        if (!client.permissionController.getGrantedPermissions().containsAll(permissions)) {
            return mapOf("satisfied" to false, "progress" to 0.0, "permissionDenied" to true)
        }
        val records = client.readRecords(
            ReadRecordsRequest(
                recordType = ExerciseSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(
                    Instant.ofEpochMilli(startMs),
                    Instant.ofEpochMilli(min(endMs, System.currentTimeMillis())),
                ),
            ),
        ).records
        var best: ExerciseSessionRecord? = null
        var bestDuration = 0L
        records.forEach { record ->
            val method = record.metadata.recordingMethod
            if (method != Metadata.RECORDING_METHOD_ACTIVELY_RECORDED &&
                method != Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED) return@forEach
            if (!matches(activity, record.exerciseType)) return@forEach
            val overlap = (min(record.endTime.toEpochMilli(), endMs) -
                max(record.startTime.toEpochMilli(), startMs)).coerceAtLeast(0L)
            if (overlap > bestDuration) { best = record; bestDuration = overlap }
        }
        val selected = best
        if (selected == null) return mapOf("satisfied" to false, "progress" to 0.0)
        val sourcePackage = selected!!.metadata.dataOrigin.packageName
        val sourceLabel = try {
            context.packageManager.getApplicationLabel(
                context.packageManager.getApplicationInfo(sourcePackage, 0),
            ).toString()
        } catch (_: Exception) { sourcePackage }
        return mapOf(
            "satisfied" to (bestDuration >= targetMs),
            "progress" to (bestDuration.toDouble() / targetMs.toDouble()).coerceIn(0.0, 1.0),
            "durationMs" to bestDuration,
            "exerciseType" to selected!!.exerciseType,
            "sourcePackage" to sourcePackage,
            "sourceLabel" to sourceLabel,
            "deviceType" to selected!!.metadata.device?.type,
            "recordId" to selected!!.metadata.id,
        )
    }

    private fun matches(activity: String, exerciseType: Int): Boolean = when (activity) {
        "strength" -> exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_STRENGTH_TRAINING
        "running" -> exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
        "cycling" -> exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_BIKING
        "yoga" -> exerciseType == ExerciseSessionRecord.EXERCISE_TYPE_YOGA
        else -> true
    }
}
