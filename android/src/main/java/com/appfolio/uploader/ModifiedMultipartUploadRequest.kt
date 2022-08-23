package com.appfolio.uploader

import android.content.Context
import com.appfolio.extensions.contentType
import com.appfolio.extensions.parameterName
import com.appfolio.extensions.remoteFileName
import net.gotev.uploadservice.UploadTask
import net.gotev.uploadservice.data.UploadFile
import net.gotev.uploadservice.protocols.multipart.MultipartUploadTask
import java.io.FileNotFoundException

class ModifiedMultipartUploadRequest(context: Context, serverUrl: String)  :
    ModifiedHttpUploadRequest<ModifiedMultipartUploadRequest>(context, serverUrl) {

  override val taskClass: Class<out UploadTask>
    get() = MultipartUploadTask::class.java

  /**
   * Adds a file to this upload request.
   *
   * @param filePath path to the file that you want to upload
   * @param parameterName Name of the form parameter that will contain file's data
   * @param fileName File name seen by the server side script. If null, the original file name
   * will be used
   * @param contentType Content type of the file. If null or empty, the mime type will be
   * automatically detected. If fore some reasons autodetection fails,
   * `application/octet-stream` will be used by default
   * @return [ModifiedMultipartUploadRequest]
   */
  @Throws(FileNotFoundException::class)
  @JvmOverloads
  fun addFileToUpload(
      filePath: String,
      parameterName: String,
      fileName: String? = null,
      contentType: String? = null
  ): ModifiedMultipartUploadRequest {
    require(filePath.isNotBlank() && parameterName.isNotBlank()) {
      "Please specify valid filePath and parameterName. They cannot be blank."
    }

    files.add(UploadFile(filePath).apply {
      this.parameterName = parameterName

      this.contentType = if (contentType.isNullOrBlank()) {
        handler.contentType(context)
      } else {
        contentType
      }

      remoteFileName = if (fileName.isNullOrBlank()) {
        handler.name(context)
      } else {
        fileName
      }
    })

    return this
  }
}
