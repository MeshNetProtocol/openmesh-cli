package com.meshnetprotocol.android.data.profile

data class SelectedProfile(
    val id: Long,
    val name: String,
    val path: String,
    val providerId: String?,
)

class ProfileRepository {
    fun selectedProfile(): SelectedProfile? = null
}
