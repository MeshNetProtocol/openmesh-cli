package com.meshnetprotocol.android.market

import android.app.Activity
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import com.google.android.material.bottomsheet.BottomSheetDialog
import com.google.android.material.card.MaterialCardView
import com.meshnetprotocol.android.R
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.provider.ProviderStorageManager
import com.meshnetprotocol.android.vpn.OpenMeshVpnService
import com.meshnetprotocol.android.vpn.VpnServiceState
import com.meshnetprotocol.android.vpn.VpnStateMachine
import androidx.core.content.ContextCompat

/**
 * 供应商选择器（简易切换界面）。
 * 对应 iOS 的 ProfileSelectionOverlay。
 */
class ProviderPickerBottomSheet(
    private val activity: Activity,
    private val onSelected: () -> Unit
) {
    private val dialog = BottomSheetDialog(activity)
    private val storage = ProviderStorageManager(activity)
    private val prefs = activity.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)

    fun show() {
        val view = LayoutInflater.from(activity).inflate(R.layout.dialog_provider_picker, null)
        dialog.setContentView(view)

        val container = view.findViewById<LinearLayout>(R.id.pickerListContainer)
        val countBadge = view.findViewById<TextView>(R.id.pickerCountBadge)

        val installedIds = storage.listInstalledProviders()
        countBadge.text = "${installedIds.size} 个配置"

        val currentSelectedId = prefs.getString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, "").orEmpty()

        val inflater = LayoutInflater.from(activity)
        installedIds.forEach { providerId ->
            val providerName = ProviderPreferences.getProviderName(activity, providerId)
            val isSelected = (providerId == currentSelectedId)
            
            val itemView = inflater.inflate(R.layout.item_provider_picker, container, false)
            val card = itemView as MaterialCardView
            val nameText = itemView.findViewById<TextView>(R.id.pickerItemName)
            val statusText = itemView.findViewById<TextView>(R.id.pickerItemStatus)
            val iconBg = itemView.findViewById<FrameLayout>(R.id.pickerItemIconBg)
            val icon = itemView.findViewById<ImageView>(R.id.pickerItemIcon)
            val check = itemView.findViewById<ImageView>(R.id.pickerItemCheck)
            val arrow = itemView.findViewById<ImageView>(R.id.pickerItemArrow)

            nameText.text = if (providerName.isEmpty()) providerId else providerName
            
            if (isSelected) {
                statusText.text = "当前使用中"
                statusText.setTextColor(ContextCompat.getColor(activity, R.color.meshBlue))
                card.setStrokeColor(ColorStateList.valueOf(ContextCompat.getColor(activity, R.color.meshBlue)))
                card.setCardBackgroundColor(Color.parseColor("#1F1C87F5")) // 12% meshBlue
                iconBg.backgroundTintList = ColorStateList.valueOf(ContextCompat.getColor(activity, R.color.meshBlue).withAlpha(41)) // 16% alpha
                icon.setImageResource(android.R.drawable.checkbox_on_background)
                icon.imageTintList = ColorStateList.valueOf(ContextCompat.getColor(activity, R.color.meshBlue))
                check.visibility = View.VISIBLE
                arrow.visibility = View.GONE
            } else {
                statusText.text = "点按切换到此供应商"
                statusText.setTextColor(Color.parseColor("#8F000000"))
                card.setStrokeColor(ColorStateList.valueOf(Color.parseColor("#1A000000")))
                card.setCardBackgroundColor(Color.WHITE)
                iconBg.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#09000000"))
                icon.setImageResource(android.R.drawable.ic_dialog_map)
                icon.imageTintList = ColorStateList.valueOf(Color.parseColor("#8F000000"))
                check.visibility = View.GONE
                arrow.visibility = View.VISIBLE
            }

            card.setOnClickListener {
                if (!isSelected) {
                    selectProvider(providerId, providerName)
                }
                dialog.dismiss()
            }

            container.addView(itemView)
        }

        dialog.show()
    }

    private fun selectProvider(providerId: String, name: String) {
        val configFile = storage.getConfigFile(providerId)
        if (!configFile.exists()) {
            Toast.makeText(activity, "配置文件丢失", Toast.LENGTH_SHORT).show()
            return
        }

        prefs.edit()
            .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, System.currentTimeMillis())
            .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, name)
            .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
            .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerId)
            .apply()

        onSelected()
    }

    private fun Int.withAlpha(alpha: Int): Int {
        return (alpha shl 24) or (this and 0x00ffffff)
    }
}
