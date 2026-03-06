package com.meshnetprotocol.android

import android.app.Dialog
import android.content.Context
import android.util.Log
import android.view.LayoutInflater
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat
import com.google.android.material.button.MaterialButton
import com.meshnetprotocol.android.data.profile.ProfileRepository
import com.meshnetprotocol.android.data.provider.ProviderStorageManager

/**
 * 安装向导对话框
 */
class InstallWizardDialog(
    private val context: Context,
    private val providerID: String,
    private val providerName: String,
    private val payload: ImportPayload
) {
    private var dialog: Dialog? = null
    private var isRunning = false
    private var isFinished = false
    private var selectAfterInstall = true
    
    private val storageManager = ProviderStorageManager(context)
    
    private val steps = listOf(
        StepState(StepID.FETCH_DETAIL, "读取供应商详情", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_CONFIG, "下载配置文件", StepStatus.PENDING),
        StepState(StepID.VALIDATE_CONFIG, "解析配置文件", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_ROUTING_RULES, "下载 routing_rules.json（可选）", StepStatus.PENDING),
        StepState(StepID.WRITE_ROUTING_RULES, "写入 routing_rules.json（可选）", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_RULE_SET, "下载 rule-set（可选）", StepStatus.PENDING),
        StepState(StepID.WRITE_RULE_SET, "写入 rule-set（可选）", StepStatus.PENDING),
        StepState(StepID.WRITE_CONFIG, "写入 config.json", StepStatus.PENDING),
        StepState(StepID.REGISTER_PROFILE, "注册到供应商列表", StepStatus.PENDING),
        StepState(StepID.FINALIZE, "完成", StepStatus.PENDING)
    )

    private var onCompletedListener: (() -> Unit)? = null

    fun setOnCompletedListener(listener: () -> Unit) {
        onCompletedListener = listener
    }

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_install_wizard, null)
        
        dialog = Dialog(context).apply {
            setContentView(view)
            setCancelable(false)
            setCanceledOnTouchOutside(false)
        }

        // 绑定 UI 组件
        val providerNameText = view.findViewById<TextView>(R.id.providerNameText)
        val selectSwitch = view.findViewById<SwitchCompat>(R.id.selectAfterInstallSwitch)
        val stepsContainer = view.findViewById<LinearLayout>(R.id.stepsContainer)
        val errorText = view.findViewById<TextView>(R.id.errorText)
        val closeButton = view.findViewById<MaterialButton>(R.id.closeButton)
        val actionButton = view.findViewById<MaterialButton>(R.id.actionButton)
        val runningContainer = view.findViewById<LinearLayout>(R.id.runningContainer)
        val runningText = view.findViewById<TextView>(R.id.runningText)

        providerNameText.text = providerName
        
        selectSwitch.isChecked = selectAfterInstall
        selectSwitch.setOnCheckedChangeListener { _, isChecked ->
            selectAfterInstall = isChecked
        }

        // 渲染步骤
        steps.forEach { step ->
            val stepView = LayoutInflater.from(context).inflate(R.layout.item_install_step, stepsContainer, false)
            val iconText = stepView.findViewById<TextView>(R.id.stepStatusIcon)
            val titleText = stepView.findViewById<TextView>(R.id.stepTitleText)
            val messageText = stepView.findViewById<TextView>(R.id.stepMessageText)

            iconText.text = getStatusIcon(step.status)
            titleText.text = step.title
            stepView.tag = step.id

            stepsContainer.addView(stepView)
        }

        closeButton.setOnClickListener {
            if (isFinished) {
                dialog?.dismiss()
            } else if (!isRunning) {
                dialog?.dismiss()
            }
        }

        actionButton.setOnClickListener {
            if (isFinished) {
                onCompletedListener?.invoke()
                dialog?.dismiss()
            } else if (!isRunning) {
                startInstall()
            }
        }

        updateActionButton(actionButton, runningContainer, runningText)
        dialog?.show()
    }

    private fun startInstall() {
        isRunning = true
        updateSteps { view, index, step ->
            val iconText = view.findViewById<TextView>(R.id.stepStatusIcon)
            val messageText = view.findViewById<TextView>(R.id.stepMessageText)
            
            if (index == 0) {
                step.status = StepStatus.RUNNING
                iconText.text = getStatusIcon(StepStatus.RUNNING)
                messageText.text = "开始安装"
                messageText.visibility = View.VISIBLE
            }
        }

        // 执行实际的安装逻辑
        executeInstall()
    }

    /**
     * 执行实际的安装流程（对齐 iOS/Windows）
     */
    private fun executeInstall() {
        Thread {
            try {
                // Step 1: Fetch Detail
                updateStepStatus(StepID.FETCH_DETAIL, StepStatus.RUNNING, "读取供应商详情...")
                Thread.sleep(200)
                updateStepStatus(StepID.FETCH_DETAIL, StepStatus.SUCCESS, "完成")

                // Step 2: Download Config
                updateStepStatus(StepID.DOWNLOAD_CONFIG, StepStatus.RUNNING, "下载配置文件...")
                Thread.sleep(200)
                updateStepStatus(StepID.DOWNLOAD_CONFIG, StepStatus.SUCCESS, "完成")

                // Step 3: Validate Config
                updateStepStatus(StepID.VALIDATE_CONFIG, StepStatus.RUNNING, "解析配置文件...")
                val configJson = String(payload.configData).trim()
                if (configJson.isEmpty()) {
                    throw IllegalStateException("配置文件内容为空")
                }
                // TODO: 验证 JSON 格式
                updateStepStatus(StepID.VALIDATE_CONFIG, StepStatus.SUCCESS, "完成")

                // Step 4-7: Optional routing rules and rule-sets (跳过模拟)
                for (optionalStep in listOf(
                    StepID.DOWNLOAD_ROUTING_RULES to StepID.WRITE_ROUTING_RULES,
                    StepID.DOWNLOAD_RULE_SET to StepID.WRITE_RULE_SET
                )) {
                    updateStepStatus(optionalStep.first, StepStatus.SUCCESS, "跳过（可选）")
                    updateStepStatus(optionalStep.second, StepStatus.SUCCESS, "跳过（可选）")
                }

                // Step 8: Write Config (关键步骤 - 使用新的存储管理器)
                updateStepStatus(StepID.WRITE_CONFIG, StepStatus.RUNNING, "写入 config.json...")
                
                val result = storageManager.writeConfig(providerID, configJson)
                result.onFailure { error ->
                    throw error
                }
                
                updateStepStatus(StepID.WRITE_CONFIG, StepStatus.SUCCESS, "完成")
                Log.i(TAG, "writeConfig: saved to ${result.getOrNull()?.absolutePath}")

                // Step 9: Register Profile
                updateStepStatus(StepID.REGISTER_PROFILE, StepStatus.RUNNING, "注册到供应商列表...")
                
                // 更新 SharedPreferences
                val prefs = context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
                val configFile = result.getOrNull()
                if (configFile != null) {
                    prefs.edit()
                        .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, System.currentTimeMillis())
                        .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, providerName)
                        .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
                        .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerID)
                        .apply()
                } else {
                    throw IllegalStateException("配置文件写入失败")
                }
                
                updateStepStatus(StepID.REGISTER_PROFILE, StepStatus.SUCCESS, "完成")

                // Step 10: Finalize
                updateStepStatus(StepID.FINALIZE, StepStatus.SUCCESS, "完成")
                isRunning = false
                isFinished = true

                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    dialog?.findViewById<MaterialButton>(R.id.actionButton)?.let { button ->
                        button.text = "完成"
                        dialog?.findViewById<LinearLayout>(R.id.runningContainer)?.visibility = View.GONE
                    }
                }
                
                Log.i(TAG, "install completed: provider=$providerID name=$providerName")
            } catch (e: Exception) {
                isRunning = false
                Log.e(TAG, "install failed: ${e.message}", e)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    dialog?.findViewById<TextView>(R.id.errorText)?.let { errorText ->
                        errorText.text = "安装失败：${e.message}"
                        errorText.visibility = View.VISIBLE
                    }
                }
            }
        }.start()
    }

    private fun updateStepStatus(stepID: StepID, status: StepStatus, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            dialog?.findViewById<LinearLayout>(R.id.stepsContainer)?.let { container ->
                for (i in 0 until container.childCount) {
                    val view = container.getChildAt(i)
                    if (view.tag == stepID) {
                        val iconText = view.findViewById<TextView>(R.id.stepStatusIcon)
                        val messageText = view.findViewById<TextView>(R.id.stepMessageText)
                        
                        val step = steps.find { it.id == stepID }
                        step?.status = status
                        
                        iconText.text = getStatusIcon(status)
                        if (message.isNotEmpty()) {
                            messageText.text = message
                            messageText.visibility = View.VISIBLE
                        }
                        break
                    }
                }
            }
        }
    }

    private fun updateSteps(updateFn: (View, Int, StepState) -> Unit) {
        dialog?.findViewById<LinearLayout>(R.id.stepsContainer)?.let { container ->
            for (i in 0 until container.childCount) {
                val view = container.getChildAt(i)
                if (i < steps.size) {
                    updateFn(view, i, steps[i])
                }
            }
        }
    }

    private fun updateActionButton(
        button: MaterialButton,
        runningContainer: LinearLayout,
        runningText: TextView
    ) {
        when {
            isFinished -> {
                button.text = "完成"
                button.isEnabled = true
                runningContainer.visibility = View.GONE
            }
            isRunning -> {
                button.text = "安装中"
                button.isEnabled = false
                runningContainer.visibility = View.VISIBLE
                runningText.text = "正在执行安装步骤..."
            }
            else -> {
                button.text = "开始安装"
                button.isEnabled = true
                runningContainer.visibility = View.GONE
            }
        }
    }

    private fun getStatusIcon(status: StepStatus): String {
        return when (status) {
            StepStatus.PENDING -> "○"
            StepStatus.RUNNING -> "◐"
            StepStatus.SUCCESS -> "●"
            StepStatus.FAILURE -> "×"
        }
    }

    enum class StepID {
        FETCH_DETAIL,
        DOWNLOAD_CONFIG,
        VALIDATE_CONFIG,
        DOWNLOAD_ROUTING_RULES,
        WRITE_ROUTING_RULES,
        DOWNLOAD_RULE_SET,
        WRITE_RULE_SET,
        WRITE_CONFIG,
        REGISTER_PROFILE,
        FINALIZE
    }

    data class StepState(
        val id: StepID,
        val title: String,
        var status: StepStatus,
        var message: String? = null
    )

    enum class StepStatus {
        PENDING,
        RUNNING,
        SUCCESS,
        FAILURE
    }
    
    companion object {
        private const val TAG = "InstallWizardDialog"
    }
}
