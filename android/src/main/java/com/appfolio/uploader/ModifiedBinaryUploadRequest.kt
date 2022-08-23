package com.appfolio.uploader
import android.content.Context
import net.gotev.uploadservice.UploadTask
import net.gotev.uploadservice.data.UploadFile
import net.gotev.uploadservice.protocols.binary.BinaryUploadRequest
import net.gotev.uploadservice.protocols.binary.BinaryUploadTask
import java.io.FileNotFoundException
import java.io.IOException

class ModifiedBinaryUploadRequest(context: Context, serverUrl: String, limitNetwork: Boolean) :
    ModifiedHttpUploadRequest<ModifiedBinaryUploadRequest>(context, serverUrl, limitNetwork) {

  override val taskClass: Class<out UploadTask>
    get() = BinaryUploadTask::class.java

  /**
   * Sets the file used as raw body of the upload request.
   *
   * @param path path to the file that you want to upload
   * @throws FileNotFoundException if the file to upload does not exist
   * @return [BinaryUploadRequest]
   */
  @Throws(IOException::class)
  fun setFileToUpload(path: String): ModifiedBinaryUploadRequest {
    files.clear()
    files.add(UploadFile(path))
    return this
  }
}
