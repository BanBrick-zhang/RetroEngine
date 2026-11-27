package com.retroengine.app

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "com.savedeck.toolkit/permission"
        private const val LAUNCHER_CHANNEL = "com.savedeck.toolkit/launcher"
        private const val RETROARCH_ACTIVITY =
            "com.retroarch.browser.retroactivity.RetroActivityFuture"
        private const val EXTERNAL_STORAGE_AUTHORITY =
            "com.android.externalstorage.documents"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openAllFilesAccessSettings" -> {
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                                intent.data = Uri.parse("package:$packageName")
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } else {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                                intent.data = Uri.parse("package:$packageName")
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    "hasAllFilesAccess" -> {
                        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Environment.isExternalStorageManager()
                        } else {
                            // API 30 以下不存在 MANAGE_EXTERNAL_STORAGE，交由 Dart 侧
                            // 处理传统的 READ/WRITE_EXTERNAL_STORAGE 权限，避免误报"已有权限"。
                            false
                        }
                        result.success(granted)
                    }
                    // 供 Dart 侧判断是否需要申请传统存储权限（API 30+ 已不适用）。
                    "sdkInt" -> result.success(Build.VERSION.SDK_INT)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LAUNCHER_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "listApps" -> {
                        try {
                            result.success(listLaunchableApps())
                        } catch (e: Exception) {
                            result.error("list_failed", e.message, null)
                        }
                    }
                    "launch" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
                            result.success(launchApp(args))
                        } catch (e: Exception) {
                            result.error("launch_failed", e.message ?: e.javaClass.simpleName, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listLaunchableApps(): List<Map<String, String>> {
        val pm = packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val resolved = pm.queryIntentActivities(intent, 0)
        val apps = LinkedHashMap<String, Map<String, String>>()
        for (info in resolved) {
            val pkg = info.activityInfo?.packageName ?: continue
            if (pkg == packageName) continue
            if (apps.containsKey(pkg)) continue
            val label = try {
                info.loadLabel(pm).toString()
            } catch (e: Exception) {
                pkg
            }
            apps[pkg] = mapOf("package" to pkg, "label" to label)
        }
        return apps.values.toList()
    }

    /**
     * 启动游戏，返回 `{direct: bool}`：
     * - true：ROM 已交给模拟器，正常情况下会直接进入游戏；
     * - false：目标应用不支持直接加载，只打开了主界面。
     *
     * 启动方式按 [mode]（Dart 侧传来的小写标识）分派。旧配置里可能还留着
     * ACTION_VIEW，这里对 AetherSX2 系应用自动改用专用启动方式。
     */
    private fun launchApp(args: Map<*, *>): Map<String, Any?> {
        val pkg = (args["package"] as? String)?.trim()
            ?: throw IllegalArgumentException("缺少目标应用包名")
        val mode = (args["mode"] as? String ?: "app").lowercase(Locale.ROOT)
        val activity = (args["activity"] as? String)?.trim().orEmpty()
        val filePath = (args["filePath"] as? String)?.trim()
        val mime = (args["mime"] as? String)?.takeIf { it.isNotBlank() } ?: "*/*"
        val core = (args["core"] as? String)?.trim().orEmpty()
        val cores = (args["cores"] as? List<*>)?.filterIsInstance<String>().orEmpty()
        val pm = packageManager

        val launchIntent = pm.getLaunchIntentForPackage(pkg)
            ?: throw IllegalStateException("应用未安装或没有启动入口")

        fun openMainScreen(): Map<String, Any?> {
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(launchIntent)
            return mapOf("direct" to false)
        }

        val rom = if (mode != "app" && !filePath.isNullOrBlank()) File(filePath) else null
        if (rom == null) return openMainScreen()
        if (!rom.exists()) {
            throw IllegalArgumentException("游戏文件不存在：${rom.absolutePath}")
        }

        // 依次尝试可用的启动方式；显式组件或 intent-filter 不匹配时跳过，
        // 而不是把“打不开游戏”当成成功。
        val builders = ArrayList<() -> LaunchAttempt>()
        when (mode) {
            "retroarch" -> builders.add { buildRetroArchIntent(pkg, activity, rom, core, cores) }
            "aethersx2" -> builders.add { buildAetherSx2Intent(pkg, activity, rom) }
            else -> {
                if (isAetherSx2Package(pkg)) {
                    builders.add { buildAetherSx2Intent(pkg, activity, rom) }
                }
                builders.add {
                    LaunchAttempt(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(contentUri(rom), mime)
                            setPackage(pkg)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        },
                        direct = true
                    )
                }
            }
        }

        for (build in builders) {
            val attempt = try {
                build()
            } catch (e: Exception) {
                continue
            }
            val intent = attempt.intent
            if (pm.resolveActivity(intent, 0) == null) continue
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return mapOf("direct" to attempt.direct)
            } catch (e: Exception) {
                // 目标应用拒绝该 intent（未导出/权限不足等），继续尝试下一种。
            }
        }
        return openMainScreen()
    }

    /** 一种启动尝试：[direct] 表示该方式是否真的把 ROM 交给了模拟器。 */
    private class LaunchAttempt(val intent: Intent, val direct: Boolean)

    private fun isAetherSx2Package(pkg: String): Boolean =
        pkg == "xyz.aethersx2.android" || pkg == "org.pcsx2.pcsx2"

    /**
     * AetherSX2 / PCSX2 Android：EmulationActivity 只认 `bootPath` 里的
     * externalstorage 文档 URI，传绝对路径会停在模拟器主界面。
     */
    private fun buildAetherSx2Intent(pkg: String, activity: String, rom: File): LaunchAttempt {
        val document = documentUri(rom)
            ?: throw IllegalStateException("无法把游戏文件转换为文档 URI")
        val targetActivity = activity.ifEmpty {
            findEmulationActivity(pkg) ?: "$pkg.EmulationActivity"
        }
        val intent = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(pkg, targetActivity)
            setDataAndType(document, "application/octet-stream")
            clipData = ClipData.newRawUri("rom", document)
            putExtra("bootPath", document.toString())
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            // 与官方推荐命令一致：清理旧任务栈，避免复用停留在主界面的实例。
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TASK)
        }
        return LaunchAttempt(intent, direct = true)
    }

    /** 在该应用内查找名为 *EmulationActivity 的 Activity（不同分支类名略有差异）。 */
    private fun findEmulationActivity(pkg: String): String? {
        return try {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(pkg, PackageManager.GET_ACTIVITIES)
                .activities
                ?.mapNotNull { it.name }
                ?.firstOrNull { it.substringAfterLast('.').endsWith("EmulationActivity") }
        } catch (e: Exception) {
            null
        }
    }

    /**
     * RetroArch：RetroActivityFuture 通过 ROM / LIBRETRO / CONFIGFILE 三个
     * extra 接收内容。核心必须传实际存在的绝对路径，否则 RetroArch 会静默
     * 退回主菜单。
     */
    private fun buildRetroArchIntent(
        pkg: String,
        activity: String,
        rom: File,
        core: String,
        cores: List<String>
    ): LaunchAttempt {
        val dataDir = File(packageManager.getApplicationInfo(pkg, 0).dataDir)
        val corePath = resolveRetroArchCore(pkg, dataDir, core, cores)
        val configFile = listOf(
            File(dataDir, "files/retroarch.cfg"),
            File(externalFilesRoot(pkg), "retroarch.cfg")
        ).firstOrNull { it.isFile }

        val intent = Intent(Intent.ACTION_MAIN).apply {
            component = ComponentName(pkg, activity.ifEmpty { RETROARCH_ACTIVITY })
            putExtra("ROM", rom.absolutePath)
            corePath?.let { putExtra("LIBRETRO", it) }
            configFile?.let { putExtra("CONFIGFILE", it.absolutePath) }
            // RetroArch 已在后台驻留时，普通 intent 只会把旧会话拉到前台，
            // 不会加载新 ROM；QUITFOCUS 让它先退出当前会话，配合 SINGLE_TOP
            // 重新走一遍 RetroActivityFuture 的启动流程。
            putExtra("QUITFOCUS", "")
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        // 找不到核心时 RetroArch 只会回到主菜单，不能算“已把 ROM 交给模拟器”。
        return LaunchAttempt(intent, direct = corePath != null)
    }

    /** 按「配置的核心 -> 平台推荐核心」顺序挑出真实存在的核心文件。 */
    private fun resolveRetroArchCore(
        pkg: String,
        dataDir: File,
        core: String,
        cores: List<String>
    ): String? {
        // 不同版本/安装方式下核心可能落在内部 dataDir/cores，或外部私有目录的
        // cores、files/cores 三处，全部纳入查找避免误判“未安装核心”。
        val externalRoot =
            "${Environment.getExternalStorageDirectory().absolutePath}/Android/data/$pkg"
        val coreDirs = listOf(
            File(dataDir, "cores"),
            File(externalRoot, "cores"),
            File(externalFilesRoot(pkg), "cores")
        )
        for (name in (listOf(core) + cores).map { it.trim() }.filter { it.isNotEmpty() }) {
            if (name.startsWith("/")) {
                if (File(name).isFile) return name
                continue
            }
            for (dir in coreDirs) {
                val file = File(dir, name)
                if (file.isFile) return file.absolutePath
            }
        }
        return null
    }

    /** 目标应用的外部私有目录：/storage/emulated/0/Android/data/<pkg>/files */
    private fun externalFilesRoot(pkg: String): String =
        "${Environment.getExternalStorageDirectory().absolutePath}/Android/data/$pkg/files"

    /**
     * 把存储中的文件转换成 ExternalStorageProvider 的「树内文档 URI」：
     * `content://com.android.externalstorage.documents/tree/<目录>/document/<文件>`。
     *
     * AetherSX2 解析 bootPath 时会按 tree/document 两级结构取目录与文件名，
     * 只给 `document/...` 形式的 URI 会被当成非法路径而退回主界面。
     * `primary:` 对应内部存储，其余卷使用卷序列号（如 `9C33-6BBD:`）。
     */
    private fun documentUri(file: File): Uri? {
        val path = try {
            file.canonicalPath
        } catch (e: Exception) {
            file.absolutePath
        }
        val primary = try {
            Environment.getExternalStorageDirectory().canonicalPath
        } catch (e: Exception) {
            Environment.getExternalStorageDirectory().absolutePath
        }.trimEnd('/')

        val documentId = when {
            path.startsWith("$primary/") -> "primary:" + path.removePrefix("$primary/")
            else -> {
                val match = Regex("^/storage/([^/]+)/(.+)$").find(path) ?: return null
                val volume = match.groupValues[1]
                val rest = match.groupValues[2]
                when (volume) {
                    "emulated", "self" -> {
                        val relative = rest.removePrefix("0/")
                        if (relative.isEmpty() || relative == rest) return null
                        "primary:$relative"
                    }
                    else -> "$volume:$rest"
                }
            }
        }
        // 目录部分作为树 ID；文件位于存储根目录时树 ID 退化为卷根（primary:）。
        val separator = documentId.lastIndexOf('/')
        val parentId = if (separator < 0) {
            "${documentId.substringBefore(':')}:"
        } else {
            documentId.substring(0, separator)
        }
        if (!parentId.contains(':')) return null
        val treeUri = DocumentsContract.buildTreeDocumentUri(
            EXTERNAL_STORAGE_AUTHORITY,
            parentId
        )
        return DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)
    }

    private fun contentUri(file: File): Uri {
        return try {
            FileProvider.getUriForFile(
                applicationContext,
                "$packageName.fileprovider",
                file
            )
        } catch (e: IllegalArgumentException) {
            throw IllegalStateException("无法把游戏文件共享给模拟器：${e.message}")
        }
    }
}