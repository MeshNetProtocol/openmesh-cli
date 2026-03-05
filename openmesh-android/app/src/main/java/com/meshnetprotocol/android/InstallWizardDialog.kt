package com.meshnetprotocol.android

import android.app.Dialog
import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat
import com.google.android.material.button.MaterialButton

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

        // TODO: 实现实际的安装逻辑
        // 这里是模拟安装过程
        simulateInstall()
    }

    private fun simulateInstall() {
        Thread {
            try {
                // 模拟每个步骤
                for ((index, step) in steps.withIndex()) {
                    if (step.id == StepID.FINALIZE) break
                    
                    updateStepStatus(step.id, StepStatus.RUNNING, "执行中...")
                    Thread.sleep(500) // 模拟执行时间
                    updateStepStatus(step.id, StepStatus.SUCCESS, "完成")
                }

                // 完成
                updateStepStatus(StepID.FINALIZE, StepStatus.SUCCESS, "完成")
                isRunning = false
                isFinished = true

                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    dialog?.findViewById<MaterialButton>(R.id.actionButton)?.let { button ->
                        button.text = "完成"
                        dialog?.findViewById<LinearLayout>(R.id.runningContainer)?.visibility = View.GONE
                    }
                }
            } catch (e: Exception) {
                isRunning = false
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
}
