package com.appfolio.uploader

import android.content.Context
import androidx.work.OneTimeWorkRequest
import androidx.work.WorkManager
import com.appfolio.extensions.setData
import com.appfolio.extensions.shouldLimitNetwork
import com.appfolio.work.UploadManager
import com.appfolio.work.UploadWorker
import net.gotev.uploadservice.HttpUploadRequest
import net.gotev.uploadservice.data.UploadTaskParameters
import java.util.*

abstract class ModifiedHttpUploadRequest<B : HttpUploadRequest<B>>(context: Context, serverUrl: String, private val limitNetwork: Boolean = false) :
    HttpUploadRequest<B>(context, serverUrl) {

  private var started: Boolean = false
  private var uploadId = UUID.randomUUID().toString()
  private val uploadTaskParameters: UploadTaskParameters
    get() = UploadTaskParameters(
        taskClass = taskClass.name,
        id = uploadId,
        serverUrl = serverUrl,
        maxRetries = maxRetries,
        autoDeleteSuccessfullyUploadedFiles = autoDeleteSuccessfullyUploadedFiles,
        files = files,
        additionalParameters = getAdditionalParameters()
    )

  override fun startUpload(): String {
    require(files.isNotEmpty()) { "Set the file to be used in the request body first!" }
    check(!started) {
      "You have already called startUpload() on this Upload request instance once and you " +
          "cannot call it multiple times. Check your code."
    }

    check(!UploadManager.taskList.contains(uploadTaskParameters.id)) {
      "You have tried to perform startUpload() using the same uploadID of an " +
          "already running task. You're trying to use the same ID for multiple uploads."
    }

    started = true
    val workManager: WorkManager = WorkManager.getInstance(context)
    val uploadRequest = OneTimeWorkRequest.Builder(UploadWorker::class.java)
    uploadRequest.shouldLimitNetwork(limitNetwork)
    uploadRequest.addTag("${UploadWorker::class.java.simpleName}-$uploadId")
    uploadRequest.setData(uploadTaskParameters, notificationConfig(context, uploadId))
    workManager.enqueue(uploadRequest.build())

    return uploadTaskParameters.id;
  }
}
