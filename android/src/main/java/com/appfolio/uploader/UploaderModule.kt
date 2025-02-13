package com.appfolio.uploader

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import android.webkit.MimeTypeMap
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.appfolio.work.UploadManager
import com.appfolio.work.UploadWorker
import com.facebook.react.BuildConfig
import com.facebook.react.bridge.*
import net.gotev.uploadservice.UploadServiceConfig.httpStack
import net.gotev.uploadservice.UploadServiceConfig.initialize
import net.gotev.uploadservice.data.UploadNotificationConfig
import net.gotev.uploadservice.data.UploadNotificationStatusConfig
import net.gotev.uploadservice.observer.request.GlobalRequestObserver
import net.gotev.uploadservice.okhttp.OkHttpStack
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.TreeMap

class UploaderModule(val reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext), LifecycleEventListener {
  private val TAG = "UploaderBridge"
  private var notificationChannelID = "BackgroundUploadChannel"
  private var isGlobalRequestObserver = false
  private var limitNetwork = false

  override fun getName(): String {
    return "RNFileUploader"
  }

  /*
    Sets uploading network limit to unmetered network.
   */
  @ReactMethod
  fun shouldLimitNetwork(limit: Boolean) {
    limitNetwork = limit;
  }

  /*
  Gets file information for the path specified.  Example valid path is: /storage/extSdCard/DCIM/Camera/20161116_074726.mp4
  Returns an object such as: {extension: "mp4", size: "3804316", exists: true, mimeType: "video/mp4", name: "20161116_074726.mp4"}
   */
  @ReactMethod
  fun getFileInfo(path: String?, promise: Promise) {
    try {
      val params = Arguments.createMap()
      val fileInfo = File(path)
      params.putString("name", fileInfo.name)
      if (!fileInfo.exists() || !fileInfo.isFile) {
        params.putBoolean("exists", false)
      } else {
        params.putBoolean("exists", true)
        params.putString("size", fileInfo.length().toString()) //use string form of long because there is no putLong and converting to int results in a max size of 17.2 gb, which could happen.  Javascript will need to convert it to a number
        val extension = MimeTypeMap.getFileExtensionFromUrl(path)
        params.putString("extension", extension)
        val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.toLowerCase())
        params.putString("mimeType", mimeType)
      }
      promise.resolve(params)
    } catch (exc: Exception) {
      exc.printStackTrace()
      Log.e(TAG, exc.message, exc)
      promise.reject(exc)
    }
  }

  private fun configureUploadServiceHTTPStack(options: ReadableMap, promise: Promise) {
    var followRedirects = true
    var followSslRedirects = true
    var retryOnConnectionFailure = true
    var connectTimeout = 45
    var writeTimeout = 90
    var readTimeout = 90
    //TODO: make 'cache' customizable
    if (options.hasKey("followRedirects")) {
      if (options.getType("followRedirects") != ReadableType.Boolean) {
        promise.reject(IllegalArgumentException("followRedirects must be a boolean."))
        return
      }
      followRedirects = options.getBoolean("followRedirects")
    }
    if (options.hasKey("followSslRedirects")) {
      if (options.getType("followSslRedirects") != ReadableType.Boolean) {
        promise.reject(IllegalArgumentException("followSslRedirects must be a boolean."))
        return
      }
      followSslRedirects = options.getBoolean("followSslRedirects")
    }
    if (options.hasKey("retryOnConnectionFailure")) {
      if (options.getType("retryOnConnectionFailure") != ReadableType.Boolean) {
        promise.reject(IllegalArgumentException("retryOnConnectionFailure must be a boolean."))
        return
      }
      retryOnConnectionFailure = options.getBoolean("retryOnConnectionFailure")
    }
    if (options.hasKey("connectTimeout")) {
      if (options.getType("connectTimeout") != ReadableType.Number) {
        promise.reject(IllegalArgumentException("connectTimeout must be a number."))
        return
      }
      connectTimeout = options.getInt("connectTimeout")
    }
    if (options.hasKey("writeTimeout")) {
      if (options.getType("writeTimeout") != ReadableType.Number) {
        promise.reject(IllegalArgumentException("writeTimeout must be a number."))
        return
      }
      writeTimeout = options.getInt("writeTimeout")
    }
    if (options.hasKey("readTimeout")) {
      if (options.getType("readTimeout") != ReadableType.Number) {
        promise.reject(IllegalArgumentException("readTimeout must be a number."))
        return
      }
      readTimeout = options.getInt("readTimeout")
    }
    httpStack = OkHttpStack(OkHttpClient().newBuilder()
            .followRedirects(followRedirects)
            .followSslRedirects(followSslRedirects)
            .retryOnConnectionFailure(retryOnConnectionFailure)
            .connectTimeout(connectTimeout.toLong(), TimeUnit.SECONDS)
            .writeTimeout(writeTimeout.toLong(), TimeUnit.SECONDS)
            .readTimeout(readTimeout.toLong(), TimeUnit.SECONDS)
            .cache(null)
            .build())
  }

  /*
   * Starts a file upload.
   * Returns a promise with the string ID of the upload.
   */
  @ReactMethod
  fun startUpload(options: ReadableMap, promise: Promise) {
    for (key in arrayOf("url", "path")) {
      if (!options.hasKey(key)) {
        promise.reject(java.lang.IllegalArgumentException("Missing '$key' field."))
        return
      }
      if (options.getType(key) != ReadableType.String) {
        promise.reject(java.lang.IllegalArgumentException("$key must be a string."))
        return
      }
    }
    if (options.hasKey("headers") && options.getType("headers") != ReadableType.Map) {
      promise.reject(java.lang.IllegalArgumentException("headers must be a hash."))
      return
    }
    if (options.hasKey("notification") && options.getType("notification") != ReadableType.Map) {
      promise.reject(java.lang.IllegalArgumentException("notification must be a hash."))
      return
    }
    configureUploadServiceHTTPStack(options, promise)
    var requestType: String? = "raw"
    if (options.hasKey("type")) {
      requestType = options.getString("type")
      if (requestType == null) {
        promise.reject(java.lang.IllegalArgumentException("type must be string."))
        return
      }
      if (requestType != "raw" && requestType != "multipart") {
        promise.reject(java.lang.IllegalArgumentException("type should be string: raw or multipart."))
        return
      }
    }
    val notification: WritableMap = WritableNativeMap()
    notification.putBoolean("enabled", true)
    if (options.hasKey("notification")) {
      notification.merge(options.getMap("notification")!!)
    }

    val application = reactContext.applicationContext as Application

    reactContext.addLifecycleEventListener(this)

    if (notification.hasKey("notificationChannel")) {
      notificationChannelID = notification.getString("notificationChannel")!!
    }

    createNotificationChannel()

    initialize(application, notificationChannelID, BuildConfig.DEBUG)

    if(!isGlobalRequestObserver) {
      isGlobalRequestObserver = true
      GlobalRequestObserver(application, GlobalRequestObserverDelegate(reactContext))
    }

    val url = options.getString("url")
    val parts = options.getArray("parts")
    val filePath = options.getString("path")
    val method = if (options.hasKey("method") && options.getType("method") == ReadableType.String) options.getString("method") else "POST"
    val maxRetries = if (options.hasKey("maxRetries") && options.getType("maxRetries") == ReadableType.Number) options.getInt("maxRetries") else 2
    val customUploadId = if (options.hasKey("customUploadId") && options.getType("method") == ReadableType.String) options.getString("customUploadId") else null
    try {
      val request = if (requestType == "raw") {
        ModifiedBinaryUploadRequest(this.reactApplicationContext, url!!, limitNetwork)
                .setFileToUpload(filePath!!)
      } else {
        if (parts == null || parts.size() < 1) {
          promise.reject(java.lang.IllegalArgumentException("For a multipart upload, parts must have size of at least 1!"))
        }

        val mRequest = ModifiedMultipartUploadRequest(this.reactApplicationContext, url!!, limitNetwork)
        val partsLength = parts?.size()

        for (i in 0 until partsLength!!) {
          val currentPart = parts?.getMap(i)
          val currentPartFieldType = currentPart?.getType("field")
          val currentPartPath = currentPart?.getString("path")
          val currentPartPathWithoutPrefix = currentPartPath?.removePrefix("file://")

          if (currentPartFieldType != ReadableType.String) {
            promise.reject(java.lang.IllegalArgumentException("The type for argument 'field' must be a string!"))
          }

          mRequest.addFileToUpload(currentPartPathWithoutPrefix!!, currentPart?.getString("field")!!)
        }
        mRequest
      }
      request.setMethod(method!!)
              .setMaxRetries(maxRetries)
      if (notification.getBoolean("enabled")) {
        val notificationConfig = UploadNotificationConfig(
                notificationChannelId = notificationChannelID,
                isRingToneEnabled = notification.hasKey("enableRingTone") && notification.getBoolean("enableRingTone"),
                progress = UploadNotificationStatusConfig(
                        title = if (notification.hasKey("onProgressTitle")) notification.getString("onProgressTitle")!! else "",
                        message = if (notification.hasKey("onProgressMessage")) notification.getString("onProgressMessage")!! else ""
                ),
                success = UploadNotificationStatusConfig(
                        title = if (notification.hasKey("onCompleteTitle")) notification.getString("onCompleteTitle")!! else "",
                        message = if (notification.hasKey("onCompleteMessage")) notification.getString("onCompleteMessage")!! else "",
                        autoClear = notification.hasKey("autoClear") && notification.getBoolean("autoClear")
                ),
                error = UploadNotificationStatusConfig(
                        title = if (notification.hasKey("onErrorTitle")) notification.getString("onErrorTitle")!! else "",
                        message = if (notification.hasKey("onErrorMessage")) notification.getString("onErrorMessage")!! else ""
                ),
                cancelled = UploadNotificationStatusConfig(
                        title = if (notification.hasKey("onCancelledTitle")) notification.getString("onCancelledTitle")!! else "",
                        message = if (notification.hasKey("onCancelledMessage")) notification.getString("onCancelledMessage")!! else ""
                )
        )
        request.setNotificationConfig { _, _ ->
          notificationConfig
        }
      }
      if (options.hasKey("parameters")) {
        if (requestType == "raw") {
          promise.reject(java.lang.IllegalArgumentException("Parameters supported only in multipart type"))
          return
        }
        val parameters = options.getMap("parameters")
        val partsOrder = options.getMap("partsOrder")
        val sortedPartsOrder = TreeMap<String, String>()
        val trackedParts = mutableListOf<String>()

        // Assert that all value parts in the partsOrder map are strings (we
        // can't assume this due to the nature of ReadableMap)
        val partsOrderIterator = partsOrder!!.keySetIterator()
        while (partsOrderIterator.hasNextKey()) {
          val key = partsOrderIterator.nextKey()

          if (partsOrder.getType(key) != ReadableType.String) {
            promise.reject(java.lang.IllegalArgumentException("Parameter value for '$key' must be a string!"))
            return
          }

          sortedPartsOrder.put(key, partsOrder.getString(key)!!)
        }

        // For each key in the sorted parts map, add it as a request parameter
        // and then add it to tracked parts 
        for ((key, value) in sortedPartsOrder) {
          if (parameters!!.getType(value) != ReadableType.String) {
            promise.reject(java.lang.IllegalArgumentException("Parameter value for '$key' must be a string!"))
            return
          }

          request.addParameter(value, parameters.getString(value)!!)
          trackedParts.add(value)
        }

        // Loop through all the parameter keys again to add any ones that may
        // not have been included in the sorted parts map
        val keys = parameters!!.keySetIterator()
        while (keys.hasNextKey()) {
          val key = keys.nextKey()

          if (trackedParts.contains(key)) {
            continue
          }

          if (parameters.getType(key) != ReadableType.String) {
            promise.reject(java.lang.IllegalArgumentException("Parameters must be string key/values. Value was invalid for '$key'"))
            return
          }
          request.addParameter(key, parameters.getString(key)!!)
        }
      }
      if (options.hasKey("headers")) {
        val headers = options.getMap("headers")
        val keys = headers!!.keySetIterator()
        while (keys.hasNextKey()) {
          val key = keys.nextKey()
          if (headers.getType(key) != ReadableType.String) {
            promise.reject(java.lang.IllegalArgumentException("Headers must be string key/values.  Value was invalid for '$key'"))
            return
          }
          request.addHeader(key, headers.getString(key)!!)
        }
      }
      if (customUploadId != null)
        request.setCustomUploadID(customUploadId)

      val uploadId = request.startUpload()
      promise.resolve(uploadId)
    } catch (exc: java.lang.Exception) {
      exc.printStackTrace()
      Log.e(TAG, exc.message, exc)
      promise.reject(exc)
    }
  }

  /*
   * Cancels file upload
   * Accepts upload ID as a first argument, this upload will be cancelled
   * Event "cancelled" will be fired when upload is cancelled.
   */
  @ReactMethod
  fun cancelUpload(cancelUploadId: String?, promise: Promise) {
    if (cancelUploadId !is String) {
      promise.reject(java.lang.IllegalArgumentException("Upload ID must be a string"))
      return
    }
    try {
      UploadManager.stopUpload(cancelUploadId)
      promise.resolve(true)
    } catch (exc: java.lang.Exception) {
      exc.printStackTrace()
      Log.e(TAG, exc.message, exc)
      promise.reject(exc)
    }
  }

  /*
   * Cancels all file uploads
   */
  @ReactMethod
  fun stopAllUploads(promise: Promise) {
    try {
      UploadManager.stopAllUploads()
      promise.resolve(true)
    } catch (exc: java.lang.Exception) {
      exc.printStackTrace()
      Log.e(TAG, exc.message, exc)
      promise.reject(exc)
    }
  }

  /*
   * Gets all file uploads with their state
   */
  @ReactMethod
  fun getAllUploads(promise: Promise) {
    val workManager: WorkManager = WorkManager.getInstance(reactContext)
    val workInfos = workManager.getWorkInfosByTag(UploadWorker::class.java.name).get()
    val uploads = Arguments.createArray()

    for (info in workInfos) {
      // Ignore 'SUCCEEDED' state from WorkManager since that only means that the uploads have started
      if (info.state === WorkInfo.State.SUCCEEDED) {
        continue
      }

      val upload = Arguments.createMap()
      
      val idTag = info.tags.toTypedArray().find { it.startsWith(UploadWorker::class.java.simpleName) }
      upload.putString("id", idTag?.removePrefix("${UploadWorker::class.java.simpleName}-"))

      when(info.state) {
        WorkInfo.State.RUNNING ->
          upload.putString("state", "running")
        WorkInfo.State.CANCELLED, WorkInfo.State.FAILED ->
          upload.putString("state", "cancelled")
        WorkInfo.State.BLOCKED, WorkInfo.State.ENQUEUED ->
          upload.putString("state", "pending")
        else ->
          continue
      }

      uploads.pushMap(upload)
    }

    val uploadTaskList = UploadManager.taskList
    for (task in uploadTaskList) {
      val upload = Arguments.createMap()
      upload.putString("id", task)
      upload.putString("state", "running")
      uploads.pushMap(upload)
    }

    promise.resolve(uploads)
  }

  // Customize the notification channel as you wish. This is only for a bare minimum example
  private fun createNotificationChannel() {
    if (Build.VERSION.SDK_INT >= 26) {
      val channel = NotificationChannel(
              notificationChannelID,
              "Background Upload Channel",
              NotificationManager.IMPORTANCE_LOW
      )
      val manager = reactApplicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
      manager.createNotificationChannel(channel)
    }
  }

  override fun onHostResume() {
  }

  override fun onHostPause() {
  }

  override fun onHostDestroy() {
  }
}
