package com.appfolio.work

import android.content.Context
import com.appfolio.extensions.UploadTaskCreationParameters
import com.appfolio.extensions.getUploadTask
import net.gotev.uploadservice.UploadTask
import net.gotev.uploadservice.data.UploadNotificationConfig
import net.gotev.uploadservice.data.UploadTaskParameters
import net.gotev.uploadservice.logger.UploadServiceLogger
import java.util.concurrent.*

class UploadManager {

  companion object {
    /**
     * Sets the Thread Pool to use for upload operations.
     * By default a thread pool with size equal to the number of processors is created.
     */
    @JvmStatic
    var threadPool: AbstractExecutorService = ThreadPoolExecutor(
        Runtime.getRuntime().availableProcessors(), // Initial pool size
        Runtime.getRuntime().availableProcessors(), // Max pool size
        5.toLong(), // Keep Alive Time
        TimeUnit.SECONDS,
        LinkedBlockingQueue<Runnable>()
    )

    val TAG: String = UploadManager::class.java.simpleName

    private const val UPLOAD_NOTIFICATION_BASE_ID = 1234 // Something unique

    private var notificationIncrementalId = 0
    private val uploadTasksMap = ConcurrentHashMap<String, UploadTask>()

    /**
     * Stops the upload task with the given uploadId.
     * @param uploadId The unique upload id
     */
    @Synchronized
    @JvmStatic
    fun stopUpload(uploadId: String) {
      uploadTasksMap[uploadId]?.cancel()
    }

    /**
     * Gets the list of the currently active upload tasks.
     * @return list of uploadIDs or an empty list if no tasks are currently running
     */
    @JvmStatic
    val taskList: List<String>
      @Synchronized get() = if (uploadTasksMap.isEmpty()) {
        emptyList()
      } else {
        uploadTasksMap.keys().toList()
      }

    /**
     * Stop all the active uploads.
     */
    @Synchronized
    @JvmStatic
    fun stopAllUploads() {
      val iterator = uploadTasksMap.keys.iterator()

      while (iterator.hasNext()) {
        uploadTasksMap[iterator.next()]?.cancel()
      }
    }

    fun startUpload(context: Context, params: UploadTaskParameters, notificationConfig: UploadNotificationConfig) {
      val taskCreationParameters = UploadTaskCreationParameters(params, notificationConfig)

      if (uploadTasksMap.containsKey(taskCreationParameters.params.id)) {
        UploadServiceLogger.error(TAG, taskCreationParameters.params.id) {
          "Preventing upload! An upload with the same ID is already in progress. " +
              "Every upload must have unique ID. Please check your code and fix it!"
        }
        return
      }

      val currentTask = context.getUploadTask(
          creationParameters = taskCreationParameters,
          notificationId = UPLOAD_NOTIFICATION_BASE_ID + notificationIncrementalId,
      ) ?: return

      uploadTasksMap[currentTask.params.id] = currentTask
      threadPool.execute(currentTask)
    }

    /**
     * Called by each task when it is completed (either successfully, with an error or due to
     * user cancellation).
     * @param uploadId the uploadID of the finished task
     */
    @Synchronized
    fun taskCompleted(uploadId: String) {
      uploadTasksMap.remove(uploadId)
    }
  }
}
