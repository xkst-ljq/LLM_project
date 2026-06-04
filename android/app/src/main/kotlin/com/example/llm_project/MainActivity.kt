package com.example.llm_project

import android.content.ContentValues
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val downloadChannel = "llm_project/download_saver"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        hideStatusBar()
    }

    override fun onResume() {
        super.onResume()
        hideStatusBar()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideStatusBar()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hideStatusBar()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadChannel
        ).setMethodCallHandler { call, result ->
            if (call.method == "saveFileToDownloads") {
                val sourcePath = call.argument<String>("sourcePath")
                val fileName = call.argument<String>("fileName")
                val subDir = call.argument<String>("subDir") ?: "LLM Project/Backups"
                val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"

                if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                    result.error("INVALID_ARGS", "sourcePath or fileName is empty", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val savedPath = saveFileToDownloads(
                            sourcePath = sourcePath,
                            fileName = fileName,
                            subDir = subDir,
                            mimeType = mimeType
                        )

                        runOnUiThread {
                            result.success(savedPath)
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("SAVE_FAILED", e.message, null)
                        }
                    }
                }.start()
            } else {
                result.notImplemented()
            }
        }
    }

    private fun saveFileToDownloads(
        sourcePath: String,
        fileName: String,
        subDir: String,
        mimeType: String
    ): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw IllegalArgumentException("Source file does not exist: $sourcePath")
        }

        val cleanSubDir = subDir.trim('/').trim()
        val relativePath = if (cleanSubDir.isEmpty()) {
            Environment.DIRECTORY_DOWNLOADS
        } else {
            Environment.DIRECTORY_DOWNLOADS + File.separator + cleanSubDir
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(
                sourceFile = sourceFile,
                fileName = fileName,
                relativePath = relativePath,
                mimeType = mimeType
            )
        } else {
            saveLegacy(
                sourceFile = sourceFile,
                fileName = fileName,
                subDir = cleanSubDir
            )
        }
    }

    private fun saveWithMediaStore(
        sourceFile: File,
        fileName: String,
        relativePath: String,
        mimeType: String
    ): String {
        val resolver = contentResolver

        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(MediaStore.Downloads.RELATIVE_PATH, relativePath)
            put(MediaStore.Downloads.IS_PENDING, 1)
        }

        val uri = resolver.insert(
            MediaStore.Downloads.EXTERNAL_CONTENT_URI,
            values
        ) ?: throw IllegalStateException("Cannot create MediaStore item")

        resolver.openOutputStream(uri)?.use { output ->
            FileInputStream(sourceFile).use { input ->
                input.copyTo(output)
            }
        } ?: throw IllegalStateException("Cannot open output stream")

        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)

        return relativePath + File.separator + fileName
    }

    private fun saveLegacy(
        sourceFile: File,
        fileName: String,
        subDir: String
    ): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )

        val targetDir = if (subDir.isEmpty()) {
            downloadsDir
        } else {
            File(downloadsDir, subDir)
        }

        if (!targetDir.exists()) {
            targetDir.mkdirs()
        }

        val targetFile = uniqueFile(targetDir, fileName)

        FileInputStream(sourceFile).use { input ->
            FileOutputStream(targetFile).use { output ->
                input.copyTo(output)
            }
        }

        return targetFile.absolutePath
    }

    private fun uniqueFile(dir: File, fileName: String): File {
        var target = File(dir, fileName)
        if (!target.exists()) return target

        val dotIndex = fileName.lastIndexOf('.')
        val name = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val ext = if (dotIndex > 0) fileName.substring(dotIndex) else ""

        var index = 1
        while (target.exists()) {
            target = File(dir, "$name ($index)$ext")
            index++
        }

        return target
    }

    @Suppress("DEPRECATION")
    private fun hideStatusBar() {
        window.decorView.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                        or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                        or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                )
    }
}