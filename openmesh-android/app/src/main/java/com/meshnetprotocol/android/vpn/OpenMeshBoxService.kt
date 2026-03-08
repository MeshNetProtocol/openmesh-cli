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
        
        return runCatching {
            var config = profileRepository.readProfileContent(profile)
            config = injectDynamicRules(config, profile)
            val adjustedConfig = optimizeRemoteRuleSets(config)
            
            val server = commandServer
            if (server != null) {
                // 原生热重载：对齐 iOS requestExtensionReload / serviceReload
                server.startOrReloadService(adjustedConfig, OverrideOptions())
                currentConfigContent = adjustedConfig
                java.io.File(profile.path).parentFile?.let { dir ->
                    // 模拟 iOS 写入 config.json
                    java.io.File(dir, "config.json").writeText(adjustedConfig)
                }
                Log.i(TAG, "Reloaded config successfully (Live Reload)")
            } else {
                val result = startWithProfile(profile)
                if (!result.ok) throw IllegalStateException(result.errorMessage)
            }
            Unit
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

    /**
     * 动态注入路由规则，对齐 iOS DynamicRoutingRules.swift 逻辑。
     * 从配置文件所在目录读取 routing_rules.json 并注入到 route.rules 中。
     */
    private fun injectDynamicRules(configContent: String, profile: SelectedProfile): String {
        try {
            val root = JSONObject(configContent)
            val profileFile = File(profile.path)
            val rulesFile = File(profileFile.parent, "routing_rules.json")
            
            if (!rulesFile.exists()) return configContent
            
            val rulesData = rulesFile.readText()
            val rulesJson = JSONObject(rulesData)
            val route = root.optJSONObject("route") ?: JSONObject().also { root.put("route", it) }
            val existingRules = route.optJSONArray("rules") ?: JSONArray().also { route.put("rules", it) }
            
            // 默认 outbound 为 "proxy" 或第一个 selector/outbound
            val outboundTag = "proxy"
            
            // 解析并转换规则 (对齐 iOS logic)
            val ipCidr = rulesJson.optJSONArray("ip_cidr")
            if (ipCidr != null && ipCidr.length() > 0) {
                val rule = JSONObject()
                rule.put("ip_cidr", ipCidr)
                rule.put("outbound", outboundTag)
                existingRules.put(rule)
            }
            
            val domain = rulesJson.optJSONArray("domain")
            if (domain != null && domain.length() > 0) {
                val rule = JSONObject()
                rule.put("domain", domain)
                rule.put("outbound", outboundTag)
                existingRules.put(rule)
            }
            
            val domainSuffix = rulesJson.optJSONArray("domain_suffix")
            if (domainSuffix != null && domainSuffix.length() > 0) {
                // 对齐 iOS: 确保 suffix 以 . 开头以匹配子域名
                val normalizedSuffix = JSONArray()
                for (i in 0 until domainSuffix.length()) {
                    val s = domainSuffix.getString(i)
                    normalizedSuffix.put(if (s.startsWith(".")) s else ".$s")
                }
                val rule = JSONObject()
                rule.put("domain_suffix", normalizedSuffix)
                rule.put("outbound", outboundTag)
                existingRules.put(rule)
            }
            
            Log.i(TAG, "injectDynamicRules: injected rules from routing_rules.json")
            return root.toString()
        } catch (e: Exception) {
            Log.e(TAG, "injectDynamicRules failed: ${e.message}")
            return configContent
        }
    }

    /**
     * 优化配置文件中的 remote rule-set，对齐 iOS MarketService.optimizeRemoteRuleSets 逻辑。
     * 1. 保持 type 为 remote，让 sing-box 原生管理下载和缓存。
     * 2. 注入 update_interval: "24h"。
     * 3. 移除不支持的 download_interval。
     */
    private fun optimizeRemoteRuleSets(configContent: String): String {
        try {
            val root = JSONObject(configContent)
            val route = root.optJSONObject("route") ?: return configContent
            val ruleSets = route.optJSONArray("rule_set") ?: return configContent

            var changed = false
            for (i in 0 until ruleSets.length()) {
                val rs = ruleSets.getJSONObject(i)
                if (rs.optString("type") == "remote") {
                    // 设置原生更新间隔
                    if (!rs.has("update_interval")) {
                        rs.put("update_interval", "24h")
                        changed = true
                    }
                    // 移除 libbox/sing-box 不支持或建议移除的旧字段
                    if (rs.has("download_interval")) {
                        rs.remove("download_interval")
                        changed = true
                    }
                    val tag = rs.optString("tag", "unknown")
                    Log.d(TAG, "optimizeRemoteRuleSets: optimized remote rule-set '$tag' for native background updates")
                }
            }
            Log.d(TAG, "optimizeRemoteRuleSets: optimization completed (changed=$changed)")
            return if (changed) root.toString() else configContent
        } catch (e: Exception) {
            Log.e(TAG, "optimizeRemoteRuleSets failed: ${e.message}")
            return configContent
        }
    }

    /**
     * 对齐 iOS/macOS/Windows Logic: 移除 inbound 中对缺失 rule-set 的引用，并调整相关路由规则。
     * 当远程 rule-set（如 geoip-cn）被移除或不可用时，需要：
     * 1. 清理 inbound 中对应的引用
     * 2. 保留 route 中的 ip_is_private 规则（但修改为只排除真正的私有地址）
     */
    private fun removeInboundRuleSetReferences(root: JSONObject): JSONObject {
        try {
            val inbounds = root.optJSONArray("inbounds") ?: return root
            
            for (i in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(i) ?: continue
                
                // 移除所有引用 rule-set 的字段（这些字段可能引用不存在的 rule-set）
                inbound.remove("route_address_set")
                inbound.remove("route_exclude_address_set")
                inbound.remove("route_include_address_set")
                inbound.remove("route_address_set_ipcidr_match_source")
                inbound.remove("route_address_set_ip_cidr_match_source")
                
                Log.d(TAG, "removeInboundRuleSetReferences: cleaned inbound '${inbound.optString("tag")}' rule-set references")
            }
            
            // 重要：保留 ip_is_private 规则，但将其 outbound 改为 proxy
            // 这样可以确保所有流量都走代理，而不是直接连接
            val route = root.optJSONObject("route")
            if (route != null) {
                val rules = route.optJSONArray("rules")
                if (rules != null) {
                    for (i in 0 until rules.length()) {
                        val rule = rules.optJSONObject(i) ?: continue
                        // 修改 ip_is_private 规则的 outbound 为 proxy
                        if (rule.has("ip_is_private") && rule.optBoolean("ip_is_private")) {
                            rule.put("outbound", "proxy")
                            Log.i(TAG, "removeInboundRuleSetReferences: changed ip_is_private rule to use proxy outbound")
                        }
                    }
                }
            }
            
            Log.i(TAG, "removeInboundRuleSetReferences: removed inbound rule-set references and updated ip_is_private rule")
            return root
        } catch (e: Exception) {
            Log.e(TAG, "removeInboundRuleSetReferences failed: ${e.message}")
            return root
        }
    }

    /**
     * 对齐 Apple 端规则顺序：先 sniff，再让 hijack-dns 命中。
     * 否则 DNS 包还没被识别成 dns，就会落入 ip_is_private 等后续规则。
     */
    private fun normalizeRouteRuleOrder(root: JSONObject): JSONObject {
        try {
            val route = root.optJSONObject("route") ?: return root
            val rules = route.optJSONArray("rules") ?: return root

            val normalized = ArrayList<JSONObject>(rules.length())
            val hijackDnsRules = ArrayList<JSONObject>()
            var sniffRule: JSONObject? = null

            for (i in 0 until rules.length()) {
                val rule = rules.optJSONObject(i) ?: continue
                when {
                    rule.optString("action") == "sniff" && sniffRule == null -> sniffRule = JSONObject(rule.toString())
                    rule.optString("action") == "hijack-dns" -> hijackDnsRules.add(JSONObject(rule.toString()))
                    else -> normalized.add(JSONObject(rule.toString()))
                }
            }

            if (sniffRule == null) {
                sniffRule = JSONObject().put("action", "sniff")
                Log.i(TAG, "normalizeRouteRuleOrder: inserted missing sniff rule")
            }

            val reordered = JSONArray()
            reordered.put(sniffRule)
            hijackDnsRules.forEach { reordered.put(it) }
            normalized.forEach { reordered.put(it) }

            route.put("rules", reordered)
            Log.i(TAG, "normalizeRouteRuleOrder: reordered route rules (sniff + ${hijackDnsRules.size} hijack-dns rules first)")
            return root
        } catch (e: Exception) {
            Log.e(TAG, "normalizeRouteRuleOrder failed: ${e.message}")
            return root
        }
    }

    /**
     * 对齐 iOS Logic: 为只有一个出端节点的 Selector/URLTest 组注入伪节点。
     * 防止 sing-box 在组内只有一个节点时可能出现的某些异常行为。
     */
    private fun injectFakeNodeForSingleNodeGroups(content: String): String {
        try {
            val root = JSONObject(content)
            val outbounds = root.optJSONArray("outbounds") ?: return content
            var needsFakeNode = false
            
            for (i in 0 until outbounds.length()) {
                val outbound = outbounds.getJSONObject(i)
                val type = outbound.optString("type").lowercase()
                if (type == "selector" || type == "urltest") {
                    val subOutbounds = outbound.optJSONArray("outbounds")
                    if (subOutbounds != null && subOutbounds.length() == 1) {
                        subOutbounds.put("fake-node-for-testing")
                        needsFakeNode = true
                        Log.d(TAG, "injectFakeNodeForSingleNodeGroups: Injected fake node into group '${outbound.optString("tag")}'")
                    }
                }
            }

            if (needsFakeNode) {
                val fakeNode = JSONObject().apply {
                    put("type", "shadowsocks")
                    put("tag", "fake-node-for-testing")
                    put("server", "127.0.0.1")
                    put("server_port", 65535)
                    put("password", "fake")
                    put("method", "aes-128-gcm")
                }
                outbounds.put(fakeNode)
                return root.toString()
            }
        } catch (e: Exception) {
            Log.w(TAG, "injectFakeNodeForSingleNodeGroups failed: ${e.message}")
        }
        return content
    }

    /**
     * 对齐 iOS Logic: 写入运行期诊断报告以便排查配置问题。
     */
    private fun writeRuntimeDiagnostics(profile: SelectedProfile, rawConfig: String, effectiveConfig: String) {
        try {
            val diag = JSONObject()
            diag.put("timestamp", java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", java.util.Locale.US).apply {
                timeZone = java.util.TimeZone.getTimeZone("UTC")
            }.format(java.util.Date()))
            diag.put("profile_id", profile.id)
            diag.put("profile_name", profile.name)
            
            // 简单摘要
            val summary = JSONObject()
            val root = JSONObject(effectiveConfig)
            val route = root.optJSONObject("route")
            if (route != null) {
                summary.put("route_final", route.optString("final"))
                val ruleSets = route.optJSONArray("rule_set")
                if (ruleSets != null) {
                    summary.put("remote_rule_set_count", ruleSets.length())
                }
            }
            diag.put("effective_summary", summary)

            val diagFile = File(vpnService.filesDir, "vpn_runtime_diag.json")
            diagFile.writeText(diag.toString(2))
            Log.i(TAG, "Runtime diagnostics written to: ${diagFile.absolutePath}")
        } catch (e: Exception) {
            Log.w(TAG, "writeRuntimeDiagnostics failed: ${e.message}")
        }
    }

    private fun startWithProfile(profile: SelectedProfile): StartResult {
        return try {
            var configContent = profileRepository.readProfileContent(profile)
            
            // 1. 注入动态规则 (routing_rules.json)
            val withDynamicRules = injectDynamicRules(configContent, profile)
            
            // 2. 注入伪节点 (对齐 iOS: 防止只有一个节点的 selector 在某些版本 sing-box 下崩溃或行为异常)
            val withFakeNode = injectFakeNodeForSingleNodeGroups(withDynamicRules)
            
            // 3. 优化远程规则集下载策略
            val optimizedConfig = optimizeRemoteRuleSets(withFakeNode)
            
            // 4. 移除 inbound 中对缺失 rule-set 的引用（对齐 iOS/macOS/Windows）
            val finalConfigRoot = normalizeRouteRuleOrder(removeInboundRuleSetReferences(JSONObject(optimizedConfig)))
            val finalConfig = finalConfigRoot.toString()

            // 5. 解析 TUN 配置选项（包括 include_package 和 exclude_package）
            val tunOptions = OpenMeshTunConfigResolver.resolve(finalConfig)
            OpenMeshVpnService.setCurrentTunOptions(tunOptions)
            Log.i(TAG, "Parsed TUN options: ${tunOptions.includePackage.count()} include packages, ${tunOptions.excludePackage.count()} exclude packages")

            // 6. 写入运行期诊断报告 (对齐 iOS)
            writeRuntimeDiagnostics(profile, configContent, finalConfig)
            
            // 7. 输出最终配置以便调试
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
        val rawConfig = profileRepository.readProfileContent(profile)
        
        // 使用与 startWithProfile 相同的处理流程
        val withDynamicRules = injectDynamicRules(rawConfig, profile)
        val withFakeNode = injectFakeNodeForSingleNodeGroups(withDynamicRules)
        val optimizedConfig = optimizeRemoteRuleSets(withFakeNode)
        val finalConfigRoot = normalizeRouteRuleOrder(removeInboundRuleSetReferences(JSONObject(optimizedConfig)))
        val finalConfig = finalConfigRoot.toString()
        
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
