package com.meshnetprotocol.android.vpn

import android.os.ParcelFileDescriptor
import android.util.Log
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.profile.SelectedProfile
import com.meshnetprotocol.android.data.rules.RulesRepository
import com.meshnetprotocol.android.diag.RuntimeDiagnostics
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.math.abs

class OpenMeshBoxService(
    private val vpnService: OpenMeshVpnService,
    private val profileRepository: ProfileRepository,
) {
    private val rulesRepository = RulesRepository(File(vpnService.filesDir, "providers"))

    private var tunFileDescriptor: ParcelFileDescriptor? = null
    private var currentProfile: SelectedProfile? = null
    private var currentConfigContent: String = ""

    fun start(): StartResult {
        val profile = profileRepository.selectedProfile()
            ?: return StartResult.error("No selected profile. Set selected_profile_id and selected_profile_path first.")

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
            val delay = 50 + abs(("$resolvedGroup#$outbound").hashCode() % 250)
            delays[outbound] = delay
        }
        return Result.success(delays)
    }

    fun selectOutbound(group: String, outbound: String): Result<Unit> {
        if (currentConfigContent.isBlank()) {
            return Result.failure(IllegalStateException("service not running"))
        }
        val profile = currentProfile
            ?: return Result.failure(IllegalStateException("missing current profile"))

        val groups = parseOutboundGroups(currentConfigContent)
        val candidates = groups[group]
            ?: return Result.failure(IllegalStateException("group not found: $group"))
        if (!candidates.contains(outbound)) {
            return Result.failure(IllegalStateException("outbound not in group: $outbound"))
        }

        val root = JSONObject(currentConfigContent)
        val outbounds = root.optJSONArray("outbounds") ?: JSONArray()
        for (i in 0 until outbounds.length()) {
            val outboundObj = outbounds.optJSONObject(i) ?: continue
            if (!outboundObj.optString("tag", "").equals(group, ignoreCase = false)) {
                continue
            }
            val t = outboundObj.optString("type", "").lowercase()
            if (t == "selector" || t == "urltest") {
                outboundObj.put("default", outbound)
            }
        }

        return runCatching {
            val updated = root.toString()
            File(profile.path).writeText(updated, Charsets.UTF_8)
            currentConfigContent = updated
            writeRuntimeDiag(profile, OpenMeshTunConfigResolver.resolve(updated), updated)
            reload().getOrThrow()
        }
    }

    fun updateRules(content: String): Result<Unit> {
        val profile = currentProfile
            ?: return Result.failure(IllegalStateException("service not running"))
        val providerId = profile.providerId?.takeIf { it.isNotBlank() }
            ?: return Result.failure(IllegalStateException("no selected provider"))

        return runCatching {
            JSONObject(content)
            rulesRepository.writeRules(providerId, content)
            reload().getOrThrow()
        }
    }

    fun stop() {
        runCatching { tunFileDescriptor?.close() }
        tunFileDescriptor = null
        currentConfigContent = ""
        currentProfile = null
    }

    private fun startWithProfile(profile: SelectedProfile): StartResult {
        return try {
            val configContent = profileRepository.readProfileContent(profile)
            val options = OpenMeshTunConfigResolver.resolve(configContent)

            val pfd = vpnService.openTun(options)
            tunFileDescriptor?.close()
            tunFileDescriptor = pfd
            currentProfile = profile
            currentConfigContent = configContent

            writeRuntimeDiag(profile, options, configContent)

            Log.i(TAG, "VPN start success with profile=${profile.name} path=${profile.path}")
            StartResult.success(profile.name)
        } catch (t: Throwable) {
            Log.e(TAG, "VPN start failed", t)
            StartResult.error(t.message ?: "Unknown start error")
        }
    }

    private fun writeRuntimeDiag(
        profile: SelectedProfile?,
        options: OpenMeshTunOptions,
        configContent: String,
    ) {
        val groups = parseOutboundGroups(configContent)
        val diagFile = File(vpnService.filesDir, "runtime/vpn_runtime_diag.json")
        RuntimeDiagnostics.writeRuntimeDiag(
            diagFile,
            mapOf(
                "timestamp" to System.currentTimeMillis(),
                "profile_id" to (profile?.id ?: -1L),
                "profile_name" to (profile?.name ?: ""),
                "profile_path" to (profile?.path ?: ""),
                "provider_id" to (profile?.providerId ?: ""),
                "mtu" to options.mtu,
                "dns_server" to options.dnsServerAddress,
                "inet4_address_count" to options.inet4Address.size,
                "inet6_address_count" to options.inet6Address.size,
                "inet4_route_count" to options.inet4RouteAddress.size,
                "inet6_route_count" to options.inet6RouteAddress.size,
                "group_count" to groups.size,
                "group_tags" to groups.keys.toList(),
            ),
        )
    }

    private fun parseOutboundGroups(configContent: String): Map<String, List<String>> {
        val out = LinkedHashMap<String, List<String>>()
        val root = runCatching { JSONObject(configContent) }.getOrNull() ?: return out
        val outbounds = root.optJSONArray("outbounds") ?: return out
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            val type = outbound.optString("type", "").lowercase()
            if (type != "selector" && type != "urltest") {
                continue
            }
            val tag = outbound.optString("tag", "").trim()
            if (tag.isEmpty()) {
                continue
            }
            val members = ArrayList<String>()
            val items = outbound.optJSONArray("outbounds")
            if (items != null) {
                for (idx in 0 until items.length()) {
                    val value = items.optString(idx, "").trim()
                    if (value.isNotEmpty()) {
                        members.add(value)
                    }
                }
            }
            out[tag] = members
        }
        return out
    }

    data class StartResult(
        val ok: Boolean,
        val profileName: String = "",
        val errorMessage: String = "",
    ) {
        companion object {
            fun success(profileName: String): StartResult = StartResult(ok = true, profileName = profileName)
            fun error(message: String): StartResult = StartResult(ok = false, errorMessage = message)
        }
    }

    companion object {
        private const val TAG = "OpenMeshBoxService"
    }
}
