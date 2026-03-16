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

    private enum class SecondaryAction { UNINSTALL, REINSTALL, NONE }
    private var secondaryAction = SecondaryAction.NONE

    init {
        val installedHashes = ProviderPreferences.getInstalledPackageHashes(context)
        val updates = ProviderPreferences.getUpdatesAvailable(context)
        
        // 优先从 hash 记录判断（精确），兼容旧版文件系统判断（fallback）
        val hashFromPrefs = installedHashes[provider.id] ?: ""
        val fileExists = com.meshnetprotocol.android.data.provider.ProviderStorageManager(context)
            .configExists(provider.id)
        
        localHash = hashFromPrefs
        isInstalled = hashFromPrefs.isNotEmpty() || fileExists
        updateAvailable = updates[provider.id] == true
    }

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_provider_detail, null)
        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
            window?.setLayout(
                android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                android.view.ViewGroup.LayoutParams.MATCH_PARENT
            )
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
        val offlineChip = view.findViewById<TextView>(R.id.detailOfflineChip)
        val offlineWarning = view.findViewById<TextView>(R.id.detailOfflineWarning)
        val primaryButton = view.findViewById<MaterialButton>(R.id.detailPrimaryActionButton)
        val secondaryButton = view.findViewById<MaterialButton>(R.id.detailSecondaryActionButton)
        val tertiaryButton = view.findViewById<MaterialButton>(R.id.detailTertiaryActionButton)
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
        val isOffline = isInstalled && !hasRemoteSource

        if (isOffline) {
            offlineChip.visibility = View.VISIBLE
            offlineWarning.visibility = View.VISIBLE
        } else {
            offlineChip.visibility = View.GONE
            offlineWarning.visibility = View.GONE
        }

        // 对应 iOS availableActions 计算逻辑
        // 主操作优先级：安装 > 更新 > 重装 > 卸载
        when {
            // 未安装 + 有来源 → 主按钮"安装"（蓝色）
            !isInstalled && hasRemoteSource -> {
                statusChip.text = "未安装"
                statusChip.setTextColor(Color.parseColor("#1C87F5"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1A1C87F5"))

                primaryButton.text = "安装"
                primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1C87F5"))
                primaryButton.setIconResource(android.R.drawable.ic_input_add)
                primaryButton.visibility = View.VISIBLE
                secondaryButton.visibility = View.GONE
                tertiaryButton.visibility = View.GONE
                secondaryAction = SecondaryAction.NONE
            }

            // 已安装 + 有更新 → 主按钮"更新"（橙色），次要按钮"重装"（青色）+"卸载"（红色）
            isInstalled && updateAvailable && hasRemoteSource -> {
                statusChip.text = "可更新"
                statusChip.setTextColor(Color.parseColor("#F5A92F"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1AF5A92F"))

                primaryButton.text = "更新"
                primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#F5A92F"))
                primaryButton.setIconResource(android.R.drawable.ic_popup_sync)
                primaryButton.visibility = View.VISIBLE

                // 次要按钮：重装（青色）
                secondaryButton.text = "重装"
                secondaryButton.setTextColor(Color.parseColor("#27B8D7"))
                secondaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#001A1A1A"))
                secondaryButton.strokeColor = ColorStateList.valueOf(Color.parseColor("#3327B8D7"))
                secondaryButton.visibility = View.VISIBLE
                secondaryAction = SecondaryAction.REINSTALL

                // 第三个按钮：卸载（红色）
                tertiaryButton.text = "卸载"
                tertiaryButton.setTextColor(Color.parseColor("#DE4A57"))
                tertiaryButton.strokeColor = ColorStateList.valueOf(Color.parseColor("#33DE4A57"))
                tertiaryButton.visibility = View.VISIBLE
                tertiaryButton.setOnClickListener {
                    dialog?.dismiss()
                    val vpnConnected = com.meshnetprotocol.android.vpn.VpnStateMachine.currentState() ==
                        com.meshnetprotocol.android.vpn.VpnServiceState.STARTED
                    val uninstallDialog = ProviderUninstallWizardDialog(
                        context, 
                        provider.id, 
                        provider.name, 
                        vpnConnected
                    )
                    uninstallDialog.setOnCompletedListener { onActionCompleted?.invoke() }
                    uninstallDialog.show()
                }
            }

            // 已安装 + 无更新 + 有来源 → 主按钮"重新安装"（青色），次要"卸载"（红色）
            isInstalled && !updateAvailable && hasRemoteSource -> {
                statusChip.text = "已安装"
                statusChip.setTextColor(Color.parseColor("#4CAF50"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1A4CAF50"))

                primaryButton.text = "重新安装"
                primaryButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#27B8D7"))
                primaryButton.setIconResource(android.R.drawable.ic_menu_share)
                primaryButton.visibility = View.VISIBLE

                secondaryButton.text = "卸载"
                secondaryButton.setTextColor(Color.parseColor("#DE4A57"))
                secondaryButton.strokeColor = ColorStateList.valueOf(Color.parseColor("#33DE4A57"))
                secondaryButton.visibility = View.VISIBLE
                tertiaryButton.visibility = View.GONE
                secondaryAction = SecondaryAction.UNINSTALL
            }

            // 已安装 + 无来源（离线）→ 主按钮隐藏，次要"卸载"（红色）
            isInstalled && !hasRemoteSource -> {
                statusChip.text = "已安装"
                statusChip.setTextColor(Color.parseColor("#4CAF50"))
                statusChip.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1A4CAF50"))

                primaryButton.visibility = View.GONE

                secondaryButton.text = "卸载"
                secondaryButton.setTextColor(Color.parseColor("#DE4A57"))
                secondaryButton.strokeColor = ColorStateList.valueOf(Color.parseColor("#33DE4A57"))
                secondaryButton.visibility = View.VISIBLE
                tertiaryButton.visibility = View.GONE
                secondaryAction = SecondaryAction.UNINSTALL
            }

            // 其他情况（未安装且无来源）→ 不显示操作按钮
            else -> {
                statusChip.text = "未安装"
                statusChip.setTextColor(Color.parseColor("#1C87F5"))
                primaryButton.visibility = View.GONE
                secondaryButton.visibility = View.GONE
                tertiaryButton.visibility = View.GONE
                secondaryAction = SecondaryAction.NONE
            }
        }

        // 事件处理
        primaryButton.setOnClickListener {
            dialog?.dismiss()
            // 所有主操作（安装/更新/重新安装）都复用安装向导
            val wizard = ProviderInstallWizardDialog(context, provider)
            wizard.setOnCompletedListener { onActionCompleted?.invoke() }
            wizard.show()
        }

        secondaryButton.setOnClickListener {
            when (secondaryAction) {
                SecondaryAction.UNINSTALL -> {
                    dialog?.dismiss()
                    val vpnConnected = com.meshnetprotocol.android.vpn.VpnStateMachine.currentState() == com.meshnetprotocol.android.vpn.VpnServiceState.STARTED
                    val uninstallDialog = ProviderUninstallWizardDialog(
                        context, 
                        provider.id, 
                        provider.name, 
                        vpnConnected
                    )
                    uninstallDialog.setOnCompletedListener { onActionCompleted?.invoke() }
                    uninstallDialog.show()
                }
                SecondaryAction.REINSTALL -> {
                    dialog?.dismiss()
                    val wizard = ProviderInstallWizardDialog(context, provider)
                    wizard.setOnCompletedListener { onActionCompleted?.invoke() }
                    wizard.show()
                }
                SecondaryAction.NONE -> { }
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
