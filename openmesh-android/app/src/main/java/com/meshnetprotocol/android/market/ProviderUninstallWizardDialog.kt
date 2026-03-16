package com.meshnetprotocol.android.market

import android.app.Dialog
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView
import com.google.android.material.button.MaterialButton
import com.meshnetprotocol.android.R
import kotlinx.coroutines.*

/**
 * 供应商卸载向导 UI (Android Sync)
 */
class ProviderUninstallWizardDialog(
    private val context: Context,
    private val providerID: String,
    private val providerName: String,
    private val vpnConnected: Boolean
) {
    private var dialog: Dialog? = null
    private var isRunning = false
    private var isFinished = false
    private var hasError = false
    private var onCompletedListener: (() -> Unit)? = null

    // 步骤 UI 状态
    data class StepViewState(
        val step: UninstallStep,
        val defaultTitle: String,
        var status: StepStatus = StepStatus.PENDING,
        var message: String? = null
    )
    enum class StepStatus { PENDING, RUNNING, SUCCESS, FAILURE }

    private val stepStates = listOf(
        StepViewState(UninstallStep.VALIDATE, "检查环境与连接状态"),
        StepViewState(UninstallStep.REMOVE_PROFILE, "删除供应商 Profile"),
        StepViewState(UninstallStep.REMOVE_PREFERENCES, "清理本地偏好设置"),
        StepViewState(UninstallStep.REMOVE_FILES, "移除配置文件与缓存"),
        StepViewState(UninstallStep.FINALIZE, "完成卸载"),
    )

    fun setOnCompletedListener(listener: () -> Unit) {
        onCompletedListener = listener
    }

    fun show() {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.dialog_provider_uninstall_wizard, null)

        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
            setCanceledOnTouchOutside(false)
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        // 绑定视图
        val nameText = view.findViewById<TextView>(R.id.wizardProviderNameText)
        val idText = view.findViewById<TextView>(R.id.wizardProviderIdText)
        val stepsContainer = view.findViewById<LinearLayout>(R.id.wizardStepsContainer)
        val errorText = view.findViewById<TextView>(R.id.wizardErrorText)
        val actionButton = view.findViewById<MaterialButton>(R.id.wizardActionButton)
        val runningContainer = view.findViewById<LinearLayout>(R.id.wizardRunningContainer)
        val runningText = view.findViewById<TextView>(R.id.wizardRunningText)
        val closeButton = view.findViewById<MaterialButton>(R.id.wizardCloseButton)

        nameText.text = providerName
        idText.text = providerID

        // 动态添加步骤行
        val inflater = LayoutInflater.from(context)
        stepStates.forEach { state ->
            val stepView = inflater.inflate(R.layout.item_install_step, stepsContainer, false)
            stepView.tag = state.step
            updateStepView(stepView, state)
            stepsContainer.addView(stepView)
        }

        actionButton.setOnClickListener {
            when {
                isFinished -> {
                    onCompletedListener?.invoke()
                    dialog?.dismiss()
                }
                hasError -> {
                    hasError = false
                    errorText.visibility = View.GONE
                    stepStates.forEach { it.status = StepStatus.PENDING; it.message = null }
                    refreshAllStepViews(stepsContainer)
                    startUninstall(stepsContainer, errorText, actionButton, runningContainer, runningText, closeButton)
                }
                !isRunning -> {
                    startUninstall(stepsContainer, errorText, actionButton, runningContainer, runningText, closeButton)
                }
            }
        }

        closeButton.setOnClickListener {
            if (!isRunning) dialog?.dismiss()
        }

        updateFooter(actionButton, runningContainer, runningText, closeButton)
        dialog?.show()
    }

    private fun startUninstall(
        stepsContainer: LinearLayout,
        errorText: TextView,
        actionButton: MaterialButton,
        runningContainer: LinearLayout,
        runningText: TextView,
        closeButton: MaterialButton
    ) {
        isRunning = true
        updateFooter(actionButton, runningContainer, runningText, closeButton)

        MainScope().launch {
            val result = ProviderUninstaller.uninstall(
                context = context,
                providerID = providerID,
                vpnConnected = vpnConnected,
                onProgress = { progress ->
                    Handler(Looper.getMainLooper()).post {
                        handleProgress(progress, stepsContainer, runningText)
                    }
                }
            )

            isRunning = false
            when (result) {
                is UninstallResult.Success -> {
                    isFinished = true
                    stepStates.find { it.step == UninstallStep.FINALIZE }?.let {
                        it.status = StepStatus.SUCCESS
                        it.message = "已安全卸载"
                    }
                    refreshAllStepViews(stepsContainer)
                }
                is UninstallResult.Failure -> {
                    hasError = true
                    errorText.text = "卸载失败：${result.error}"
                    errorText.visibility = View.VISIBLE
                    stepStates.find { it.step == result.step }?.let {
                        it.status = StepStatus.FAILURE
                        it.message = result.error
                    }
                    refreshAllStepViews(stepsContainer)
                }
            }
            updateFooter(actionButton, runningContainer, runningText, closeButton)
        }
    }

    private fun handleProgress(
        progress: UninstallProgress,
        stepsContainer: LinearLayout,
        runningText: TextView
    ) {
        val state = stepStates.find { it.step == progress.step } ?: return
        
        // 将其它运行中的步骤设为 Success (卸载通常是顺序完成的)
        stepStates.forEach { 
             if (it.step != progress.step && it.status == StepStatus.RUNNING) {
                 it.status = StepStatus.SUCCESS
             }
        }

        state.status = StepStatus.RUNNING
        state.message = progress.message

        refreshAllStepViews(stepsContainer)
        runningText.text = progress.message
    }

    private fun refreshAllStepViews(stepsContainer: LinearLayout) {
        for (i in 0 until stepsContainer.childCount) {
            val view = stepsContainer.getChildAt(i)
            val step = view.tag as? UninstallStep ?: continue
            val state = stepStates.find { it.step == step } ?: continue
            updateStepView(view, state)
        }
    }

    private fun updateStepView(view: View, state: StepViewState) {
        view.findViewById<TextView>(R.id.stepStatusIcon).apply {
            text = getStatusIcon(state.status)
            setTextColor(getStatusColor(state.status))
        }
        view.findViewById<TextView>(R.id.stepTitleText).text = state.defaultTitle
        view.findViewById<TextView>(R.id.stepMessageText).apply {
            if (!state.message.isNullOrEmpty()) {
                text = state.message
                visibility = View.VISIBLE
            } else {
                visibility = View.GONE
            }
        }
    }

    private fun updateFooter(
        actionButton: MaterialButton,
        runningContainer: LinearLayout,
        runningText: TextView,
        closeButton: MaterialButton
    ) {
        when {
            isFinished -> {
                actionButton.text = "已完成"
                actionButton.isEnabled = true
                actionButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#4CAF50"))
                runningContainer.visibility = View.GONE
                closeButton.apply {
                    text = "关闭"
                    isEnabled = true
                }
            }
            isRunning -> {
                actionButton.text = "正在卸载…"
                actionButton.isEnabled = false
                runningContainer.visibility = View.VISIBLE
                closeButton.isEnabled = false
            }
            hasError -> {
                actionButton.text = "重试"
                actionButton.isEnabled = true
                actionButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#EA5961"))
                runningContainer.visibility = View.GONE
                closeButton.apply {
                    text = "取消"
                    isEnabled = true
                }
            }
            else -> {
                actionButton.text = "立即卸载"
                actionButton.isEnabled = true
                runningContainer.visibility = View.GONE
                closeButton.isEnabled = true
            }
        }
    }

    private fun getStatusIcon(status: StepStatus): String = when (status) {
        StepStatus.PENDING -> "○"
        StepStatus.RUNNING -> "◐"
        StepStatus.SUCCESS -> "●"
        StepStatus.FAILURE -> "×"
    }

    private fun getStatusColor(status: StepStatus): Int = when (status) {
        StepStatus.PENDING -> Color.parseColor("#94000000")
        StepStatus.RUNNING -> Color.parseColor("#EA5961")
        StepStatus.SUCCESS -> Color.parseColor("#009E54")
        StepStatus.FAILURE -> Color.parseColor("#DE4A57")
    }
}
