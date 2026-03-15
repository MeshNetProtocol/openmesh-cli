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
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

/**
 * 供应商卸载向导 UI
 */
class ProviderUninstallDialog(
    private val context: Context,
    private val providerID: String,
    private val providerName: String,
    private val vpnConnected: Boolean,
    private val onCompleted: (() -> Unit)? = null
) {
    private var dialog: Dialog? = null
    private var isRunning = false
    private var isFinished = false
    private var hasError = false

    // 步骤 UI 状态列表
    data class StepViewState(
        val step: UninstallStep,
        val defaultTitle: String,
        var status: StepStatus = StepStatus.PENDING,
        var message: String? = null
    )
    enum class StepStatus { PENDING, RUNNING, SUCCESS, FAILURE }

    private val stepStates = listOf(
        StepViewState(UninstallStep.VALIDATE, "校验状态"),
        StepViewState(UninstallStep.REMOVE_PROFILE, "删除 Profile 记录"),
        StepViewState(UninstallStep.REMOVE_PREFERENCES, "清理偏好映射"),
        StepViewState(UninstallStep.REMOVE_FILES, "删除缓存文件"),
        StepViewState(UninstallStep.FINALIZE, "完成")
    )

    fun show() {
        val view = LayoutInflater.from(context).inflate(R.layout.dialog_provider_uninstall, null)
        dialog = Dialog(context, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
            setContentView(view)
            setCancelable(false)
            setCanceledOnTouchOutside(false)
            window?.setLayout(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT
            )
        }

        val nameText = view.findViewById<TextView>(R.id.uninstallProviderName)
        val idText = view.findViewById<TextView>(R.id.uninstallProviderID)
        val stepsContainer = view.findViewById<LinearLayout>(R.id.uninstallStepsContainer)
        val statusText = view.findViewById<TextView>(R.id.uninstallStatusText)
        val actionButton = view.findViewById<MaterialButton>(R.id.uninstallActionButton)
        val closeButton = view.findViewById<MaterialButton>(R.id.uninstallCloseButton)

        nameText.text = providerName.ifEmpty { providerID }
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
                    onCompleted?.invoke()
                    dialog?.dismiss()
                }
                hasError -> {
                    startUninstall(stepsContainer, statusText, actionButton, closeButton)
                }
                !isRunning -> {
                    startUninstall(stepsContainer, statusText, actionButton, closeButton)
                }
            }
        }

        closeButton.setOnClickListener {
            if (!isRunning) dialog?.dismiss()
        }

        dialog?.show()
    }

    private fun startUninstall(
        stepsContainer: LinearLayout,
        statusText: TextView,
        actionButton: MaterialButton,
        closeButton: MaterialButton
    ) {
        isRunning = true
        hasError = false
        statusText.visibility = View.GONE
        actionButton.isEnabled = false
        actionButton.text = "正在卸载..."
        closeButton.isEnabled = false

        MainScope().launch {
            val result = ProviderUninstaller.uninstall(
                context = context,
                providerID = providerID,
                vpnConnected = vpnConnected,
                onProgress = { progress ->
                    Handler(Looper.getMainLooper()).post {
                        handleProgress(progress, stepsContainer)
                    }
                }
            )

            isRunning = false
            when (result) {
                is UninstallResult.Success -> {
                    isFinished = true
                    stepStates.find { it.step == UninstallStep.FINALIZE }?.let {
                        it.status = StepStatus.SUCCESS
                        it.message = "完成"
                    }
                    refreshAllStepViews(stepsContainer)
                    actionButton.text = "完成"
                    actionButton.isEnabled = true
                    actionButton.backgroundTintList = ColorStateList.valueOf(Color.parseColor("#1C87F5"))
                    closeButton.isEnabled = true
                }
                is UninstallResult.Failure -> {
                    hasError = true
                    statusText.text = "卸载失败：${result.error}"
                    statusText.visibility = View.VISIBLE
                    stepStates.find { it.step == result.step }?.let {
                        it.status = StepStatus.FAILURE
                        it.message = result.error
                    }
                    refreshAllStepViews(stepsContainer)
                    actionButton.text = "重试"
                    actionButton.isEnabled = true
                    closeButton.isEnabled = true
                }
            }
        }
    }

    private fun handleProgress(progress: UninstallProgress, stepsContainer: LinearLayout) {
        val state = stepStates.find { it.step == progress.step } ?: return
        stepStates.find { it.status == StepStatus.RUNNING && it.step != progress.step }?.let {
            it.status = StepStatus.SUCCESS
        }
        state.status = StepStatus.RUNNING
        state.message = progress.message
        refreshAllStepViews(stepsContainer)
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

    private fun getStatusIcon(status: StepStatus): String = when (status) {
        StepStatus.PENDING -> "○"
        StepStatus.RUNNING -> "◐"
        StepStatus.SUCCESS -> "●"
        StepStatus.FAILURE -> "×"
    }

    private fun getStatusColor(status: StepStatus): Int = when (status) {
        StepStatus.PENDING -> Color.parseColor("#94000000")
        StepStatus.RUNNING -> Color.parseColor("#1C87F5")
        StepStatus.SUCCESS -> Color.parseColor("#009E54")
        StepStatus.FAILURE -> Color.parseColor("#DE4A57")
    }
}
