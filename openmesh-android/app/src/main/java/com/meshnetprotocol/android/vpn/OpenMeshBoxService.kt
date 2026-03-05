package com.meshnetprotocol.android.vpn

import android.os.ParcelFileDescriptor
import android.util.Log
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.diag.RuntimeDiagnostics
import java.io.File

class OpenMeshBoxService(
    private val vpnService: OpenMeshVpnService,
    private val profileRepository: ProfileRepository,
) {
    private var tunFileDescriptor: ParcelFileDescriptor? = null

    fun start(): StartResult {
        val profile = profileRepository.selectedProfile()
            ?: return StartResult.error("No selected profile. Set selected_profile_id and selected_profile_path first.")

        return try {
            val configContent = profileRepository.readProfileContent(profile)
            val options = OpenMeshTunConfigResolver.resolve(configContent)

            val pfd = vpnService.openTun(options)
            tunFileDescriptor?.close()
            tunFileDescriptor = pfd

            val diagFile = File(vpnService.filesDir, "runtime/vpn_runtime_diag.json")
            RuntimeDiagnostics.writeRuntimeDiag(
                diagFile,
                mapOf(
                    "timestamp" to System.currentTimeMillis(),
                    "profile_id" to profile.id,
                    "profile_name" to profile.name,
                    "profile_path" to profile.path,
                    "provider_id" to (profile.providerId ?: ""),
                    "mtu" to options.mtu,
                    "dns_server" to options.dnsServerAddress,
                    "inet4_address_count" to options.inet4Address.size,
                    "inet6_address_count" to options.inet6Address.size,
                    "inet4_route_count" to options.inet4RouteAddress.size,
                    "inet6_route_count" to options.inet6RouteAddress.size,
                ),
            )

            Log.i(TAG, "VPN start success with profile=${profile.name} path=${profile.path}")
            StartResult.success(profile.name)
        } catch (t: Throwable) {
            Log.e(TAG, "VPN start failed", t)
            StartResult.error(t.message ?: "Unknown start error")
        }
    }

    fun stop() {
        runCatching { tunFileDescriptor?.close() }
        tunFileDescriptor = null
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
