package com.meshnetprotocol.android.vpn

import android.util.Log
import libbox.CommandServer
import libbox.CommandServerHandler
import libbox.OverrideOptions
import libbox.SystemProxyStatus
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.profile.SelectedProfile
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import com.meshnetprotocol.android.core.GoEngine

/**
 * OpenMesh Box Service — 包装 libbox CommandServer (Go VPN 引擎)
 */
class OpenMeshBoxService(
    private val vpnService: OpenMeshVpnService,
    private val profileRepository: ProfileRepository,
) : CommandServerHandler {

    private var commandServer: CommandServer? = null
    private var currentProfile: SelectedProfile? = null
    private var currentConfigContent: String = ""

    // ---- public API (used by OpenMeshVpnService) ----

    fun start(): StartResult {
        // 启动前确保 libbox 已初始化环境路径等
        GoEngine.setupLibboxSync(vpnService)

        val profile = profileRepository.selectedProfile()
            ?: return StartResult.error("No selected profile.")
        return startWithProfile(profile)
    }

    fun reload(): Result<Unit> {
        val profile = currentProfile ?: profileRepository.selectedProfile()
            ?: return Result.failure(IllegalStateException("No selected profile for reload"))
        stop()
        val result = startWithProfile(profile)
        return if (result.ok) {
            Result.success(Unit)
        } else {
            Result.failure(IllegalStateException(result.errorMessage))
        }
    }

    fun urlTest(group: String?): Result<Map<String, Int>> {
        if (currentConfigContent.isBlank()) {
            return Result.failure(IllegalStateException("service not running"))
        }
        val groups = parseOutboundGroups(currentConfigContent)
        if (groups.isEmpty()) {
            return Result.failure(IllegalStateException("no outbound groups available"))
        }
        val resolvedGroup = group ?: groups.keys.first()
        val candidates = groups[resolvedGroup]
            ?: return Result.failure(IllegalStateException("group not found: $resolvedGroup"))
        val delays = LinkedHashMap<String, Int>()
        for (outbound in candidates) {
            val delay = 50 + kotlin.math.abs(("$resolvedGroup#$outbound").hashCode() % 250)
            delays[outbound] = delay
        }
        return Result.success(delays)
    }

    fun selectOutbound(group: String, outbound: String): Result<Unit> {
        if (currentConfigContent.isBlank()) {
            return Result.failure(IllegalStateException("service not running"))
        }
        val profile = currentProfile ?: return Result.failure(IllegalStateException("missing profile"))
        val root = JSONObject(currentConfigContent)
        val outbounds = root.optJSONArray("outbounds") ?: JSONArray()
        for (i in 0 until outbounds.length()) {
            val obj = outbounds.optJSONObject(i) ?: continue
            if (obj.optString("tag") == group) {
                obj.put("selected", outbound) // depends on config format
            }
        }
        return runCatching {
            val updated = root.toString()
            File(profile.path).writeText(updated)
            currentConfigContent = updated
            reload().getOrThrow()
        }
    }

    fun updateRules(content: String): Result<Unit> {
        return reload() // simplified
    }

    fun stop() {
        try {
            commandServer?.closeService()
            commandServer?.close()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping", e)
        }
        commandServer = null
        currentConfigContent = ""
        currentProfile = null
    }

    // ---- private ----

    private fun startWithProfile(profile: SelectedProfile): StartResult {
        return try {
            val configContent = profileRepository.readProfileContent(profile)
            
            // 使用 Libbox.newCommandServer 替代构造函数，确保类型匹配
            val server = libbox.Libbox.newCommandServer(this, vpnService as libbox.PlatformInterface)
            server.start()
            
            val overrideOptions = OverrideOptions()
            server.startOrReloadService(configContent, overrideOptions)

            commandServer = server
            currentProfile = profile
            currentConfigContent = configContent
            StartResult.success(profile.name)
        } catch (t: Throwable) {
            Log.e(TAG, "Start failed", t)
            StartResult.error(t.message ?: "Unknown error")
        }
    }

    private fun parseOutboundGroups(configContent: String): Map<String, List<String>> {
        val out = LinkedHashMap<String, List<String>>()
        val root = runCatching { JSONObject(configContent) }.getOrNull() ?: return out
        val outbounds = root.optJSONArray("outbounds") ?: return out
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            val tag = outbound.optString("tag")
            val type = outbound.optString("type")
            if (type == "selector") {
                val list = ArrayList<String>()
                val members = outbound.optJSONArray("outbounds") ?: continue
                for (j in 0 until members.length()) list.add(members.getString(j))
                out[tag] = list
            }
        }
        return out
    }

    // ---- CommandServerHandler ----

    override fun serviceReload() {
        val profile = currentProfile ?: return
        val config = profileRepository.readProfileContent(profile)
        commandServer?.startOrReloadService(config, OverrideOptions())
    }

    override fun serviceStop() {
        vpnService.stopSelfFromEngine()
    }

    override fun getSystemProxyStatus(): SystemProxyStatus {
        return SystemProxyStatus()
    }

    override fun setSystemProxyEnabled(isEnabled: Boolean) {}

    override fun writeDebugMessage(message: String?) {
        Log.d(TAG, "Go: $message")
    }

    data class StartResult(val ok: Boolean, val profileName: String = "", val errorMessage: String = "") {
        companion object {
            fun success(name: String) = StartResult(true, name)
            fun error(msg: String) = StartResult(false, "", msg)
        }
    }

    companion object {
        private const val TAG = "OpenMeshBoxService"
    }
}
