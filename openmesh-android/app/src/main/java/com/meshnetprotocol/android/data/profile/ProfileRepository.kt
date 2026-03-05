package com.meshnetprotocol.android.data.profile

import android.content.Context
import java.io.File

data class SelectedProfile(
    val id: Long,
    val name: String,
    val path: String,
    val providerId: String?,
)

class ProfileRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun selectedProfile(): SelectedProfile? {
        val id = prefs.getLong(KEY_SELECTED_PROFILE_ID, -1L)
        val path = prefs.getString(KEY_SELECTED_PROFILE_PATH, null)?.trim().orEmpty()
        if (id < 0 || path.isEmpty()) {
            return null
        }

        val name = prefs.getString(KEY_SELECTED_PROFILE_NAME, null)?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: "Profile-$id"
        val providerId = prefs.getString(KEY_SELECTED_PROVIDER_ID, null)?.trim()
            ?.takeIf { it.isNotEmpty() }
        return SelectedProfile(
            id = id,
            name = name,
            path = path,
            providerId = providerId,
        )
    }

    fun readProfileContent(profile: SelectedProfile): String {
        val profileFile = File(profile.path)
        if (!profileFile.exists()) {
            throw IllegalStateException("Selected profile file does not exist: ${profile.path}")
        }
        if (!profileFile.isFile) {
            throw IllegalStateException("Selected profile path is not a file: ${profile.path}")
        }
        val content = profileFile.readText(Charsets.UTF_8).trim()
        if (content.isEmpty()) {
            throw IllegalStateException("Selected profile is empty: ${profile.path}")
        }
        return content
    }

    companion object {
        const val PREFS_NAME = "openmesh_vpn"
        const val KEY_SELECTED_PROFILE_ID = "selected_profile_id"
        const val KEY_SELECTED_PROFILE_NAME = "selected_profile_name"
        const val KEY_SELECTED_PROFILE_PATH = "selected_profile_path"
        const val KEY_SELECTED_PROVIDER_ID = "selected_provider_id"
    }
}
