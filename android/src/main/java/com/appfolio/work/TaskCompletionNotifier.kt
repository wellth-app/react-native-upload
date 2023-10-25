package com.appfolio.work

import net.gotev.uploadservice.data.UploadInfo
import net.gotev.uploadservice.data.UploadNotificationConfig
import net.gotev.uploadservice.network.ServerResponse
import net.gotev.uploadservice.observer.task.UploadTaskObserver

class TaskCompletionNotifier : UploadTaskObserver {
  override fun onStart(
      info: UploadInfo,
      notificationId: Int,
      notificationConfig: UploadNotificationConfig
  ) {
  }

  override fun onProgress(
      info: UploadInfo,
      notificationId: Int,
      notificationConfig: UploadNotificationConfig
  ) {
  }

  override fun onSuccess(
      info: UploadInfo,
      notificationId: Int,
      notificationConfig: UploadNotificationConfig,
      response: ServerResponse
  ) {
  }

  override fun onError(
      info: UploadInfo,
      notificationId: Int,
      notificationConfig: UploadNotificationConfig,
      exception: Throwable
  ) {
    UploadManager.taskFailed(info.uploadId)
  }

  override fun onCompleted(
      info: UploadInfo,
      notificationId: Int,
      notificationConfig: UploadNotificationConfig
  ) {
    UploadManager.taskCompleted(info.uploadId)
  }
}
