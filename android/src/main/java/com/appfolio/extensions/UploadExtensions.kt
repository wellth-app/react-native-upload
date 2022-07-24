package com.appfolio.extensions

import androidx.work.Data
import androidx.work.OneTimeWorkRequest
import com.google.gson.Gson
import net.gotev.uploadservice.data.UploadFile
import net.gotev.uploadservice.data.UploadNotificationConfig
import net.gotev.uploadservice.data.UploadTaskParameters
import net.gotev.uploadservice.extensions.setOrRemove
import net.gotev.uploadservice.persistence.PersistableData

private const val PROPERTY_PARAM_NAME = "multipartParamName"
private const val PROPERTY_REMOTE_FILE_NAME = "multipartRemoteFileName"
private const val PROPERTY_CONTENT_TYPE = "multipartContentType"
const val PARAM_KEY_TASK_PARAMS = "PARAM_KEY_TASK_PARAMS"
const val PARAM_KEY_NOTIF_CONFIG = "PARAM_KEY_NOTIF_CONFIG"

internal var UploadFile.parameterName: String?
  get() = properties[PROPERTY_PARAM_NAME]
  set(value) {
    properties.setOrRemove(PROPERTY_PARAM_NAME, value)
  }

internal var UploadFile.remoteFileName: String?
  get() = properties[PROPERTY_REMOTE_FILE_NAME]
  set(value) {
    properties.setOrRemove(PROPERTY_REMOTE_FILE_NAME, value)
  }

internal var UploadFile.contentType: String?
  get() = properties[PROPERTY_CONTENT_TYPE]
  set(value) {
    properties.setOrRemove(PROPERTY_CONTENT_TYPE, value)
  }

internal fun UploadTaskParameters.toJson(): String = toPersistableData().toJson()

internal fun String.toUploadTaskParameters(): UploadTaskParameters = UploadTaskParameters.createFromPersistableData(PersistableData.fromJson(this))

internal fun UploadNotificationConfig.toJson(): String = Gson().toJson(this)

internal fun String.toUploadNotificationConfig() = Gson().fromJson(this, UploadNotificationConfig::class.java)

internal fun OneTimeWorkRequest.Builder.setData(uploadTaskParameters: UploadTaskParameters, notificationConfig: UploadNotificationConfig) {
  val data = Data.Builder()
  data.putString(PARAM_KEY_TASK_PARAMS, uploadTaskParameters.toJson())
  data.putString(PARAM_KEY_NOTIF_CONFIG, notificationConfig.toJson())
  setInputData(data.build())
}
