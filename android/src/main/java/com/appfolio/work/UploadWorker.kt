package com.appfolio.work

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.google.gson.Gson
import net.gotev.uploadservice.data.UploadNotificationConfig
import net.gotev.uploadservice.data.UploadTaskParameters
import net.gotev.uploadservice.persistence.PersistableData

class UploadWorker(val context: Context, params: WorkerParameters): Worker(context, params) {

  companion object {
    const val PARAM_KEY_TASK_PARAMS = "TASK_PARAMS"
    const val PARAM_KEY_NOTIF_CONFIG = "NOTIF_CONFIG"
  }

  override fun doWork(): Result {
    val gson = Gson()
    val taskParamsStr = inputData.getString(PARAM_KEY_TASK_PARAMS)
    val uploadTaskParameters= UploadTaskParameters.createFromPersistableData(PersistableData.fromJson(taskParamsStr!!))
    val configStr = inputData.getString(PARAM_KEY_NOTIF_CONFIG)
    val notificationConfig = gson.fromJson(configStr, UploadNotificationConfig::class.java)

    UploadManager.startUpload(context, uploadTaskParameters, notificationConfig)
    return Result.success()
  }
}
