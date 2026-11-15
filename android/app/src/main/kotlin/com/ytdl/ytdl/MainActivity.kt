package com.ytdl.ytdl

import android.content.ContentValues
import android.content.Intent
import android.os.Environment
import android.provider.MediaStore
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

/**
 * yt-dlp(youtubedl-android) 를 Flutter 에서 쓰기 위한 플랫폼 채널.
 *
 *  - ytdl/native   (MethodChannel) : init / getInfo / download / cancel / update / getSharedText
 *  - ytdl/progress (EventChannel)  : 다운로드 중 yt-dlp 출력 한 줄씩 전달
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newCachedThreadPool()
    private var events: EventChannel.EventSink? = null
    private var channel: MethodChannel? = null
    private var sharedText: String? = null
    private var initialized = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sharedText = extractSharedText(intent)

        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EventChannel(messenger, "ytdl/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                events = sink
            }

            override fun onCancel(arguments: Any?) {
                events = null
            }
        })

        channel = MethodChannel(messenger, "ytdl/native").also { ch ->
            ch.setMethodCallHandler { call, result -> handle(call, result) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        extractSharedText(intent)?.let { channel?.invokeMethod("sharedText", it) }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            return intent.getStringExtra(Intent.EXTRA_TEXT)
        }
        return null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> async(result) {
                ensureInit()
                YoutubeDL.version(applicationContext)
            }

            "getInfo" -> async(result) {
                ensureInit()
                val req = YoutubeDLRequest(call.argument<String>("url")!!)
                req.addOption("--dump-single-json")
                req.addOption("--no-playlist")
                req.addOption("--no-warnings")
                YoutubeDL.execute(req).out
            }

            "download" -> async(result) {
                ensureInit()
                val id = call.argument<String>("id")!!
                val url = call.argument<String>("url")!!
                val args = call.argument<List<String>>("args")!!
                val audio = call.argument<Boolean>("audio") ?: true

                val tmp = File(getExternalFilesDir(null) ?: filesDir, "tmp/$id").apply {
                    deleteRecursively()
                    mkdirs()
                }
                try {
                    val req = YoutubeDLRequest(url)
                    req.addOption("-P", tmp.absolutePath)
                    req.addCommands(args)
                    val resp = YoutubeDL.execute(req, processId = id, callback = { _, _, line ->
                        runOnUiThread { events?.success(mapOf("id" to id, "line" to line)) }
                    })

                    // yt-dlp 가 --print 로 알려 준 최종 경로, 없으면 임시 폴더에서 가장 최근 파일.
                    val reported = resp.out.lineSequence()
                        .lastOrNull { it.startsWith("YTDL_FILE:") }
                        ?.removePrefix("YTDL_FILE:")?.trim()
                        ?.let { File(it) }
                    val file = reported?.takeIf { it.exists() }
                        ?: tmp.listFiles()
                            ?.filter { it.isFile && !it.name.endsWith(".part") }
                            ?.maxByOrNull { it.lastModified() }
                        ?: throw IOException("받은 파일을 찾지 못했습니다.")
                    publish(file, audio)
                } finally {
                    tmp.deleteRecursively()
                }
            }

            // 이미 저장한 음원의 일부만 다시 잘라 새 파일로 저장(재인코딩 없이 복사).
            "trimAudio" -> async(result) {
                ensureInit()
                val src = File(call.argument<String>("src")!!)
                if (!src.exists()) throw IOException("원본 파일을 찾을 수 없습니다.")
                val startMs = call.argument<Number>("startMs")!!.toLong()
                val endMs = call.argument<Number>("endMs")!!.toLong()
                val outName = call.argument<String>("outName")!!

                val tmp = File(getExternalFilesDir(null) ?: filesDir, "tmp/trim${System.nanoTime()}").apply {
                    mkdirs()
                }
                try {
                    val out = File(tmp, outName)
                    runFfmpeg(
                        listOf(
                            "-nostdin", "-y", "-loglevel", "error",
                            "-i", src.absolutePath,
                            "-ss", "%.3f".format(java.util.Locale.US, startMs / 1000.0),
                            "-t", "%.3f".format(java.util.Locale.US, (endMs - startMs) / 1000.0),
                            "-map_metadata", "0",
                            "-c", "copy",
                            out.absolutePath,
                        )
                    )
                    if (!out.exists() || out.length() == 0L) throw IOException("잘라낸 파일이 비어 있습니다.")
                    publish(out, true)
                } finally {
                    tmp.deleteRecursively()
                }
            }

            "cancel" -> {
                YoutubeDL.destroyProcessById(call.argument<String>("id")!!)
                result.success(true)
            }

            "update" -> async(result) {
                ensureInit()
                YoutubeDL.updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)?.name ?: "UNKNOWN"
            }

            "getSharedText" -> {
                result.success(sharedText)
                sharedText = null
            }

            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        YoutubeDL.init(applicationContext)
        FFmpeg.init(applicationContext)
        initialized = true
    }

    /**
     * 앱에 내장된 ffmpeg(libffmpeg.so) 를 직접 실행한다.
     * 이 실행 파일이 쓰는 공유 라이브러리가 압축 해제된 폴더(ffmpeg/python)와 앱 네이티브 폴더에 흩어져 있어
     * LD_LIBRARY_PATH 로 알려 줘야 한다(youtubedl-android 가 yt-dlp 에 해 주는 것과 같은 설정).
     */
    private fun runFfmpeg(args: List<String>) {
        val libDir = applicationInfo.nativeLibraryDir
        val pkg = File(noBackupFilesDir, "youtubedl-android/packages")
        val bin = File(libDir, "libffmpeg.so")
        if (!bin.exists()) throw IOException("내장 ffmpeg 를 찾을 수 없습니다.")

        val pb = ProcessBuilder(listOf(bin.absolutePath) + args).redirectErrorStream(true)
        pb.environment()["LD_LIBRARY_PATH"] = listOf(
            File(pkg, "ffmpeg/usr/lib").absolutePath,
            File(pkg, "python/usr/lib").absolutePath,
            libDir,
        ).joinToString(":")
        val proc = pb.start()
        val log = proc.inputStream.bufferedReader().readText()
        val code = proc.waitFor()
        if (code != 0) throw IOException("ffmpeg 실패($code): ${log.takeLast(300).trim()}")
    }

    /** 무거운 작업을 백그라운드 스레드에서 돌리고 결과를 UI 스레드로 돌려준다. */
    private fun async(result: MethodChannel.Result, block: () -> Any?) {
        executor.execute {
            try {
                val r = block()
                runOnUiThread { result.success(r) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("ERR", e.message ?: e.toString(), null) }
            }
        }
    }

    /** 받은 파일을 MediaStore 로 옮겨 Music/YTDL, Movies/YTDL 에 보이게 한다(권한 불필요). */
    private fun publish(file: File, audio: Boolean): Map<String, String> {
        val mime = when (file.extension.lowercase()) {
            "mp3" -> "audio/mpeg"
            "m4a" -> "audio/mp4"
            "opus", "ogg" -> "audio/ogg"
            "mp4" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> if (audio) "audio/webm" else "video/webm"
            else -> if (audio) "audio/*" else "video/*"
        }
        val relative = if (audio) "Music/YTDL" else "Movies/YTDL"
        val collection = if (audio) {
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, file.name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val resolver = contentResolver
        val uri = resolver.insert(collection, values) ?: throw IOException("저장 공간에 파일을 만들지 못했습니다.")
        try {
            resolver.openOutputStream(uri)!!.use { out -> file.inputStream().use { it.copyTo(out) } }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Throwable) {
            resolver.delete(uri, null, null)
            throw e
        }

        // 같은 이름이 있으면 MediaStore 가 이름을 바꾸므로 실제로 저장된 이름을 다시 읽는다.
        var savedName = file.name
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) savedName = c.getString(0)
        }
        val root = Environment.getExternalStoragePublicDirectory(
            if (audio) Environment.DIRECTORY_MUSIC else Environment.DIRECTORY_MOVIES
        )
        return mapOf(
            "location" to "$relative/$savedName",
            "path" to File(File(root, "YTDL"), savedName).absolutePath,
        )
    }
}
