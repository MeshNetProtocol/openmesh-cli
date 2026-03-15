package com.meshnetprotocol.android.market

import android.app.Dialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.view.LayoutInflater
import android.view.View
import android.widget.TextView
import com.google.android.material.button.MaterialButton
import com.meshnetprotocol.android.R

/**
 * 供应商详情对话框。
 * 提供安装、更新、重新安装和卸载操作入口。
 */
class ProviderDetailDialog(
    private val context: Context,
    private val provider: TrafficProvider,
    private val onActionCompleted: (() -> Unit)? = null
) {
    private var dialog: Dialog? = null
    private val localHash: String
    private val isInstalled: Boolean
    private val updateAvailable: Boolean

    init {
        val installedHashes = ProviderPreferences.getInstalledPackageHashes(context)
        val updates = ProviderPreferences.getUpdatesAvailable(context)
        localHash = installedHashes[provider.id] ?: ""
        isInstalled = localHash.isNotEmpty()
        updateAvailable = updates[provider.id] == true
    }

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_provider_detail, null)
        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
        }

        // 视图绑定
        val nameText = view.findViewById<TextView>(R.id.detailProviderName)
        val idText = view.findViewById<TextView>(R.id.detailProviderID)
        val descriptionText = view.findViewById<TextView>(R.id.detailDescription)
        val authorText = view.findViewById<TextView>(R.id.detailAuthor)
        val updatedAtText = view.findViewById<TextView>(R.id.detailUpdatedAt)
        val localHashText = view.findViewById<TextView>(R.id.detailLocalHash)
        val remoteHashText = view.findViewById<TextView>(R.id.detailRemoteHash)
        val tagsText = view.findViewById<TextView>(R.id.detailTags)
        val statusChip = view.findViewById<TextView>(R.id.detailStatusChip)
        val priceChip = view.findViewById<TextView>(R.id.detailPriceChip)
        val primaryButton = view.findViewById<MaterialButton>(R.id.detailPrimaryActionButton)
        val secondaryButton = view.findViewById<MaterialButton>(R.id.detailSecondaryActionButton)
        val closeButton = view.findViewById<MaterialButton>(R.id.detailCloseButton)

        // 填充数据
        nameText.text = provider.name
        idText.text = formatProviderID(provider.id)
        descriptionText.text = provider.description.ifEmpty { "暂无描述" }
        authorText.text = provider.author.ifEmpty { "Unknown" }
        updatedAtText.text = provider.updated_at.take(10).ifEmpty { "—" }

        localHashText.text = formatHash(localHash)
        remoteHashText.text = formatHash(provider.package_hash ?: "")

        if (provider.tags.isNotEmpty()) {
            tagsText.text = "标签: " + provider.tags.take(5).joinToString(" · ")
            tagsText.visibility = View.VISIBLE
        }

        if (provider.price_per_gb_usd != null) {
            priceChip.text = String.format("%.2f USD/GB", provider.price_per_gb_usd)
            priceChip.visibility = View.VISIBLE
        }

        // 状态和操作配置
        val hasRemoteSource = (provider.package_hash ?: "").isNotEmpty() || provider.config_url.isNotEmpty()

        when {
            updateAvailable -> {
                statusChip.text = "可更新"
                statusChip.setTextColor(Color.parseColor("#F5A92F"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1AF5A92F"))

                primaryButton.text = "更新"
                primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#F5A92F"))

                secondaryButton.visibility = View.VISIBLE
                secondaryButton.text = "卸载"
            }
            isInstalled -> {
                statusChip.text = "已安装"
                statusChip.setTextColor(Color.parseColor("#009E54"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1A009E54"))

                if (hasRemoteSource) {
                    primaryButton.text = "重新安装"
                    primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#27B8D7"))
                } else {
                    primaryButton.visibility = View.GONE
                }

                secondaryButton.visibility = View.VISIBLE
                secondaryButton.text = "卸载"
            }
            else -> {
                statusChip.text = "未安装"
                statusChip.setTextColor(Color.parseColor("#1C87F5"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1A1C87F5"))

                primaryButton.text = "安装"
                primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1C87F5"))

                secondaryButton.visibility = View.GONE
            }
        }

        // 事件处理
        primaryButton.setOnClickListener {
            dialog?.dismiss()
            val wizard = ProviderInstallWizardDialog(context, provider)
            wizard.setOnCompletedListener { onActionCompleted?.invoke() }
            wizard.show()
        }

        secondaryButton.setOnClickListener {
            if (secondaryButton.text == "卸载") {
                dialog?.dismiss()
                val vpnConnected = com.meshnetprotocol.android.vpn.VpnStateMachine.currentState() == com.meshnetprotocol.android.vpn.VpnServiceState.STARTED
                val uninstallDialog = ProviderUninstallDialog(
                    context, 
                    provider.id, 
                    provider.name, 
                    vpnConnected,
                    onCompleted = { onActionCompleted?.invoke() }
                )
                uninstallDialog.show()
            }
        }

        closeButton.setOnClickListener {
            dialog?.dismiss()
        }

        dialog?.show()
    }

    private fun formatProviderID(id: String): String {
        return if (id.length > 30) {
            id.take(10) + "..." + id.takeLast(8)
        } else {
            id
        }
    }

    private fun formatHash(hash: String): String {
        if (hash.isEmpty()) return "—"
        return if (hash.length > 14) {
            hash.take(6) + "..." + hash.takeLast(6)
        } else {
            hash
        }
    }
}
