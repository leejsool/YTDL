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
import java.nio.file.Files
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * yt-dlp(youtubedl-android) 를 Flutter 에서 쓰기 위한 플랫폼 채널.
 *
 *  - ytdl/native   (MethodChannel) : init / getInfo / download / cancel / update / getSharedText
 *  - ytdl/progress (EventChannel)  : 다운로드 중 yt-dlp 출력 한 줄씩 전달
 */
class MainActivity : FlutterActivity() {
    private val executor = Executors.newCachedThreadPool()
    private val gainProbes = ConcurrentHashMap<String, GainProbe>()

    private class GainProbe {
        @Volatile var cancelled = false
        @Volatile var process: Process? = null

        fun check() {
            if (cancelled) throw IOException("음량 분석을 취소했습니다.")
        }

        fun cancel() {
            cancelled = true
            process?.destroy()
        }
    }
    private var events: EventChannel.EventSink? = null
    private var channel: MethodChannel? = null
    private var sharedText: String? = null
    private var initialized = false

    /** 저장 폴더 이름(Music/<이름>, Movies/<이름>). 옵션 탭에서 바꾼다. */
    @Volatile private var folderName = "YTDL"

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
                if (call.argument<Boolean>("playlist") == true) {
                    // 재생목록: 영상마다 분석하지 않고 목록만 읽는다.
                    req.addOption("--flat-playlist")
                    req.addOption("--yes-playlist")
                    req.addOption("--playlist-end", (call.argument<Number>("limit")?.toInt() ?: 200).toString())
                } else {
                    req.addOption("--no-playlist")
                }
                req.addOption("--no-warnings")
                // HLS 목록은 쓰지 않는다(받아 오는 시간만 늘어난다).
                req.addOption("--extractor-args", "youtube:skip=hls")
                YoutubeDL.execute(req).out
            }

            "measureGain" -> {
                val id = call.argument<String>("id")!!
                val probe = GainProbe()
                gainProbes[id] = probe
                async(result) {
                    try {
                        measureGain(call, id, probe)
                    } finally {
                        gainProbes.remove(id)
                    }
                }
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
                var infoFile: File? = null
                try {
                    // 조회 때 받아 둔 JSON 이 있으면 분석을 건너뛴다(--load-info-json). 없으면 주소로 받는다.
                    val infoJson = call.argument<String>("infoJson")
                    val req = if (infoJson != null) {
                        // 받은 파일을 찾을 때 섞이지 않게 임시 폴더 바깥에 둔다.
                        val f = File(tmp.parentFile, "$id.info.json")
                        infoFile = f
                        f.writeText(infoJson, Charsets.UTF_8)
                        YoutubeDLRequest(emptyList<String>()).apply {
                            addOption("--load-info-json", f.absolutePath)
                        }
                    } else YoutubeDLRequest(url)
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

                    // 음량 조절: 받은 파일을 내장 ffmpeg 로 같은 형식으로 다시 인코딩한 뒤 저장한다.
                    val gainArgs = call.argument<List<String>>("gainArgs")
                    val finalFile = if (audio && gainArgs != null) {
                        runOnUiThread { events?.success(mapOf("id" to id, "line" to "YTDL_GAIN")) }
                        val out = File(File(tmp, "gain").apply { mkdirs() }, file.name)
                        runFfmpeg(
                            listOf("-nostdin", "-y", "-loglevel", "error",
                                "-i", file.absolutePath, "-map_metadata", "0") +
                                gainArgs + out.absolutePath
                        )
                        if (!out.exists() || out.length() == 0L) throw IOException("음량을 바꾼 파일이 비어 있습니다.")
                        out
                    } else file
                    publish(finalFile, audio)
                } finally {
                    tmp.deleteRecursively()
                    infoFile?.delete()
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
                // 음량을 바꿀 때만 값이 온다(다시 인코딩). 없으면 그대로 복사.
                val encodeArgs = call.argument<List<String>>("encodeArgs") ?: listOf("-c", "copy")

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
                        ) + encodeArgs + out.absolutePath
                    )
                    if (!out.exists() || out.length() == 0L) throw IOException("잘라낸 파일이 비어 있습니다.")
                    publish(out, true)
                } finally {
                    tmp.deleteRecursively()
                }
            }

            // 미리듣기: 유튜브 소리의 일부 구간만 받아 캐시 폴더에 둔다(저장소에 올리지 않음).
            "previewSegment" -> async(result) {
                ensureInit()
                val id = call.argument<String>("id")!!
                val url = call.argument<String>("url")!!
                val args = call.argument<List<String>>("args")!!
                val root = File(cacheDir, "preview").apply { mkdirs() }
                // 오래된 미리듣기 파일 정리(10분 지난 것)
                root.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > 600_000 }
                    ?.forEach { it.deleteRecursively() }
                val dir = File(root, id).apply { deleteRecursively(); mkdirs() }
                val req = YoutubeDLRequest(url)
                req.addOption("-P", dir.absolutePath)
                req.addCommands(args)
                val resp = YoutubeDL.execute(req, processId = id, callback = { _, _, _ -> })
                val reported = resp.out.lineSequence()
                    .lastOrNull { it.startsWith("YTDL_FILE:") }
                    ?.removePrefix("YTDL_FILE:")?.trim()?.let { File(it) }
                val file = reported?.takeIf { it.exists() }
                    ?: dir.listFiles()?.filter { it.isFile && !it.name.endsWith(".part") }
                        ?.maxByOrNull { it.lastModified() }
                    ?: throw IOException("미리듣기 소리를 받지 못했습니다.")
                file.absolutePath
            }

            // 미리듣기: 받은 소리(또는 파일의 일부)에 음량 조절을 적용해 재생용 m4a 로 만든다.
            "previewGain" -> async(result) {
                ensureInit()
                val src = call.argument<String>("src")!!
                val out = File(File(cacheDir, "preview").apply { mkdirs() }, call.argument<String>("outName")!!)
                val startSec = call.argument<Number>("startSec")?.toDouble()
                val endSec = call.argument<Number>("endSec")?.toDouble()
                val args = call.argument<List<String>>("args")!!
                if (!out.exists() || out.length() == 0L) {
                    out.parentFile?.mkdirs()
                    val range = if (startSec != null && endSec != null) listOf(
                        "-ss", "%.3f".format(java.util.Locale.US, startSec),
                        "-t", "%.3f".format(java.util.Locale.US, endSec - startSec),
                    ) else emptyList()
                    runFfmpeg(
                        listOf("-nostdin", "-y", "-loglevel", "error") + range +
                            listOf("-i", src) + args + out.absolutePath
                    )
                    if (!out.exists() || out.length() == 0L) throw IOException("미리듣기 파일이 비어 있습니다.")
                    trimPreviewCache(out)
                }
                out.absolutePath
            }

            // 영상 자르기: 시작 지점을 입력 앞에 두어 빠르게 찾고, 결과를 Movies/YTDL 에 저장한다.
            "trimVideo" -> async(result) {
                ensureInit()
                val src = File(call.argument<String>("src")!!)
                if (!src.exists()) throw IOException("원본 파일을 찾을 수 없습니다.")
                val startMs = call.argument<Number>("startMs")!!.toLong()
                val endMs = call.argument<Number>("endMs")!!.toLong()
                val outName = call.argument<String>("outName")!!
                val args = call.argument<List<String>>("args")!!

                val tmp = File(getExternalFilesDir(null) ?: filesDir, "tmp/vtrim${System.nanoTime()}").apply {
                    mkdirs()
                }
                try {
                    val out = File(tmp, outName)
                    runFfmpeg(
                        listOf(
                            "-nostdin", "-y", "-loglevel", "error",
                            "-ss", "%.3f".format(java.util.Locale.US, startMs / 1000.0),
                            "-i", src.absolutePath,
                            "-t", "%.3f".format(java.util.Locale.US, (endMs - startMs) / 1000.0),
                            "-map_metadata", "0",
                        ) + args + out.absolutePath
                    )
                    if (!out.exists() || out.length() == 0L) throw IOException("잘라낸 영상이 비어 있습니다.")
                    publish(out, false)
                } finally {
                    tmp.deleteRecursively()
                }
            }

            "cancel" -> {
                val id = call.argument<String>("id")!!
                gainProbes[id]?.cancel()
                YoutubeDL.destroyProcessById(id)
                result.success(true)
            }

            "update" -> async(result) {
                ensureInit()
                YoutubeDL.updateYoutubeDL(applicationContext, YoutubeDL.UpdateChannel.STABLE)?.name ?: "UNKNOWN"
            }

            "setFolder" -> {
                folderName = call.argument<String>("name") ?: "YTDL"
                result.success(true)
            }

            "getSharedText" -> {
                result.success(sharedText)
                sharedText = null
            }

            else -> result.notImplemented()
        }
    }

    /** 미리듣기 임시 파일(특히 압축 없는 wav)이 쌓이지 않게, 총 400MB 를 넘으면 오래된 것부터 지운다. */
    private fun trimPreviewCache(keep: File) {
        val root = File(cacheDir, "preview")
        val all = root.walkTopDown().filter { it.isFile && it != keep }.sortedBy { it.lastModified() }.toMutableList()
        var total = all.sumOf { it.length() } + keep.length()
        val limit = 400L * 1024 * 1024
        for (f in all) {
            if (total <= limit) break
            total -= f.length()
            f.delete()
        }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        YoutubeDL.init(applicationContext)
        FFmpeg.init(applicationContext)
        initialized = true
    }

    private fun measureGain(call: MethodCall, id: String, probe: GainProbe): String {
        ensureInit()
        probe.check()
        val source = call.argument<String>("source")!!
        val downloadArgs = call.argument<List<String>>("downloadArgs")
        val args = call.argument<List<String>>("measureArgs")!!
        val tmp = downloadArgs?.let { Files.createTempDirectory(cacheDir.toPath(), "gain-").toFile() }
        try {
            val input = if (tmp != null) {
                val req = YoutubeDLRequest(source)
                req.addOption("-P", tmp.absolutePath)
                req.addCommands(downloadArgs)
                probe.check()
                val output = YoutubeDL.execute(req, processId = id, callback = { _, _, _ ->
                    if (probe.cancelled) YoutubeDL.destroyProcessById(id)
                }).out
                output.lineSequence().lastOrNull { it.startsWith("YTDL_FILE:") }
                    ?.removePrefix("YTDL_FILE:")?.trim()
                    ?: throw IOException("분석할 음원을 받지 못했습니다.")
            } else source
            probe.check()
            return runFfmpeg(args.map { if (it == "YTDL_AUDIO_INPUT") input else it }, probe)
        } finally {
            tmp?.deleteRecursively()
        }
    }

    /**
     * 앱에 내장된 ffmpeg(libffmpeg.so) 를 직접 실행한다.
     * 이 실행 파일이 쓰는 공유 라이브러리가 압축 해제된 폴더(ffmpeg/python)와 앱 네이티브 폴더에 흩어져 있어
     * LD_LIBRARY_PATH 로 알려 줘야 한다(youtubedl-android 가 yt-dlp 에 해 주는 것과 같은 설정).
     */
    private fun runFfmpeg(args: List<String>, probe: GainProbe? = null): String {
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
        if (probe != null) {
            probe.process = proc
            if (probe.cancelled) proc.destroy()
        }
        val log = proc.inputStream.bufferedReader().use { it.readText() }
        val code = proc.waitFor()
        probe?.check()
        if (code != 0) throw IOException("ffmpeg 실패($code): ${log.takeLast(300).trim()}")
        return log
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
        val relative = if (audio) "Music/$folderName" else "Movies/$folderName"
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
            "path" to File(File(root, folderName), savedName).absolutePath,
        )
    }
}
