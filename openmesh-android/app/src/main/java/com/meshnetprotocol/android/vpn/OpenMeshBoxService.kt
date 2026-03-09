package com.meshnetprotocol.android.vpn

import android.content.Context
import android.net.ConnectivityManager
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
        
        return runCatching {
            val adjustedConfig = prepareRuntimeConfig(profile)
            
            val server = commandServer
            if (server != null) {
                // 原生热重载：对齐 iOS requestExtensionReload / serviceReload
                server.startOrReloadService(adjustedConfig, OverrideOptions())
                currentConfigContent = adjustedConfig
                Log.i(TAG, "Reloaded config successfully (Live Reload)")
            } else {
                val result = startWithProfile(profile)
                if (!result.ok) throw IllegalStateException(result.errorMessage)
            }
            Unit
        }
    }

    private fun prepareRuntimeConfig(profile: SelectedProfile): String {
        val rawConfig = profileRepository.readProfileContent(profile)
        Log.i(TAG, "prepareRuntimeConfig: rawConfig length=${rawConfig.length}")

        val routingRules = loadRoutingRules(profile)
        val mergedConfig = OpenMeshRoutingRuleInjector.inject(rawConfig, routingRules)
        val sanitizedConfig = OpenMeshConfigSanitizer.sanitize(mergedConfig)
        val connectivity =
            vpnService.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val underlyingNetwork = OpenMeshDefaultNetworkMonitor.currentOrSelect(vpnService)
        val enableIpv6 =
            OpenMeshDefaultNetworkMonitor.hasUsableIpv6(connectivity, underlyingNetwork)
        val finalConfig = OpenMeshConfigSanitizer.adaptTunAddressFamilies(
            sanitizedConfig,
            enableIpv6 = enableIpv6
        )
        Log.i(TAG, "prepareRuntimeConfig: tun IPv6 enabled=$enableIpv6")
        Log.i(TAG, "prepareRuntimeConfig: finalConfig length=${finalConfig.length}")


        return finalConfig
    }

    private fun loadRoutingRules(profile: SelectedProfile): String? {
        val profileFile = File(profile.path)
        val rulesFile = profileFile.parentFile?.let { File(it, "routing_rules.json") }
        if (rulesFile == null) {
            Log.i(TAG, "prepareRuntimeConfig: profile has no parent directory, skip routing_rules.json lookup")
            return null
        }
        if (!rulesFile.exists() || !rulesFile.isFile) {
            Log.i(TAG, "prepareRuntimeConfig: no routing_rules.json found at ${rulesFile.absolutePath}")
            return null
        }

        return try {
            rulesFile.readText(Charsets.UTF_8).trim().takeIf { it.isNotEmpty() }?.also {
                Log.i(TAG, "prepareRuntimeConfig: loaded routing_rules.json from ${rulesFile.absolutePath}")
            }
        } catch (e: Exception) {
            Log.w(TAG, "prepareRuntimeConfig: failed to read routing_rules.json: ${e.message}")
            null
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

    private var lastRuntimeDiagFingerprint: String? = null

    /**
     * 对齐 iOS Logic: 写入运行期诊断报告以便排查配置问题。
     */
    private fun writeRuntimeDiagnostics(profile: SelectedProfile, rawConfig: String, effectiveConfig: String) {
        try {
            val rawSummary = configSummary(rawConfig)
            val effectiveSummary = configSummary(effectiveConfig)

            val fingerprintObj = JSONObject().apply {
                put("profile_id", profile.id)
                put("profile_name", profile.name)
                put("profile_path", profile.path)
                put("raw", rawSummary)
                put("effective", effectiveSummary)
            }
            val fingerprint = fingerprintObj.toString()

            val diagFile = File(vpnService.filesDir, "vpn_runtime_diag.json")
            if (lastRuntimeDiagFingerprint == fingerprint && diagFile.exists()) {
                return
            }

            val diag = JSONObject()
            diag.put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(java.util.Date()))
            diag.put("profile_id", profile.id)
            diag.put("profile_name", profile.name)
            diag.put("profile_path", profile.path)
            diag.put("raw", rawSummary)
            diag.put("effective", effectiveSummary)

            diagFile.writeText(diag.toString(2))
            lastRuntimeDiagFingerprint = fingerprint
            Log.i(TAG, "Runtime diagnostics written to: ${diagFile.absolutePath}")
        } catch (e: Exception) {
            Log.w(TAG, "writeRuntimeDiagnostics failed: ${e.message}")
        }
    }

    private fun configSummary(content: String): JSONObject {
        val summary = JSONObject()
        val root = runCatching { JSONObject(content) }.getOrNull() ?: return summary.apply { put("parse_ok", false) }
        summary.put("parse_ok", true)

        val route = root.optJSONObject("route")
        if (route != null) {
            summary.put("route_final", route.optString("final", ""))
            val ruleSets = route.optJSONArray("rule_set")
            if (ruleSets != null) {
                val remoteTags = JSONArray()
                for (i in 0 until ruleSets.length()) {
                    val rs = ruleSets.optJSONObject(i) ?: continue
                    if (rs.optString("type") == "remote") {
                        val tag = rs.optString("tag")
                        if (tag.isNotEmpty()) remoteTags.put(tag)
                    }
                }
                summary.put("remote_rule_set_tags", remoteTags)
                summary.put("remote_rule_set_count", remoteTags.length())
            } else {
                summary.put("remote_rule_set_tags", JSONArray())
                summary.put("remote_rule_set_count", 0)
            }
        }

        val dns = root.optJSONObject("dns")
        if (dns != null) {
            summary.put("dns_final", dns.optString("final", ""))
        } else {
            summary.put("dns_final", "")
        }
        
        val outboundTags = JSONArray()
        val selectorDefaults = JSONObject()
        val outbounds = root.optJSONArray("outbounds")
        if (outbounds != null) {
            for (i in 0 until outbounds.length()) {
                val out = outbounds.optJSONObject(i) ?: continue
                val tag = out.optString("tag")
                if (tag.isNotEmpty()) {
                    outboundTags.put(tag)
                    if (out.optString("type", "").equals("selector", ignoreCase = true)) {
                        selectorDefaults.put(tag, out.optString("default", ""))
                    }
                }
            }
        }
        summary.put("outbound_tags", outboundTags)
        summary.put("selector_defaults", selectorDefaults)

        return summary
    }

    private fun startWithProfile(profile: SelectedProfile): StartResult {
        return try {
            val configContent = profileRepository.readProfileContent(profile)
            val finalConfig = prepareRuntimeConfig(profile)

            // 5. 写入运行期诊断报告 (对齐 iOS)
            writeRuntimeDiagnostics(profile, configContent, finalConfig)
            
            // 6. 输出最终配置以便调试
            Log.i(TAG, "VPN configuration processed successfully")
            Log.i(TAG, "Final config summary:")
            val root = JSONObject(finalConfig)
            val route = root.optJSONObject("route")
            if (route != null) {
                val rules = route.optJSONArray("rules")
                if (rules != null) {
                    Log.i(TAG, "Route rules count: ${rules.length()}")
                    for (i in 0 until rules.length()) {
                        val rule = rules.optJSONObject(i) ?: continue
                        val outbound = rule.optString("outbound", "<default>")
                        val hasIpPrivate = rule.has("ip_is_private")
                        val hasDomainSuffix = rule.has("domain_suffix")
                        val hasProtocol = rule.has("protocol")
                        Log.i(TAG, "  Rule[$i]: outbound=$outbound, ip_private=$hasIpPrivate, domain_suffix=$hasDomainSuffix, protocol=$hasProtocol")
                    }
                }
            }

            // 使用 Libbox.newCommandServer 替代构造函数，确保类型匹配
            val server = libbox.Libbox.newCommandServer(this, vpnService as libbox.PlatformInterface)
            server.start()
            
            val overrideOptions = OverrideOptions()
            server.startOrReloadService(finalConfig, overrideOptions)

            commandServer = server
            currentProfile = profile
            currentConfigContent = finalConfig
            Log.i(TAG, "VPN service started successfully with profile: ${profile.name}")
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
        Log.i(TAG, "serviceReload triggered for profile: ${profile.name}")
        val finalConfig = prepareRuntimeConfig(profile)
        
        currentConfigContent = finalConfig
        try {
            commandServer?.startOrReloadService(finalConfig, OverrideOptions())
            Log.i(TAG, "serviceReload completed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "serviceReload failed: ${e.message}")
        }
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
