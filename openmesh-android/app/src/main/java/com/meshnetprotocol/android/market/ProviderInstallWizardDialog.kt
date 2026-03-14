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
import android.widget.ProgressBar
import android.widget.TextView
import androidx.appcompat.widget.SwitchCompat
import com.google.android.material.button.MaterialButton
import com.meshnetprotocol.android.R
import kotlinx.coroutines.*

/**
 * 供应商安装向导 UI
 */
class ProviderInstallWizardDialog(
    private val context: Context,
    private val provider: TrafficProvider
) {
    private var dialog: Dialog? = null
    private var isRunning = false
    private var isFinished = false
    private var hasError = false
    private var selectAfterInstall = true
    private var onCompletedListener: (() -> Unit)? = null

    // 步骤 UI 状态列表（与 InstallStep 一一对应）
    data class StepViewState(
        val step: InstallStep,
        val defaultTitle: String,
        var status: StepStatus = StepStatus.PENDING,
        var message: String? = null
    )
    enum class StepStatus { PENDING, RUNNING, SUCCESS, FAILURE }

    // 初始步骤列表
    private val stepStates = listOf(
        StepViewState(InstallStep.FETCH_DETAIL, "读取供应商详情"),
        StepViewState(InstallStep.DOWNLOAD_CONFIG, "下载配置文件"),
        StepViewState(InstallStep.VALIDATE_CONFIG, "解析配置文件"),
        StepViewState(InstallStep.DOWNLOAD_ROUTING_RULES, "下载 routing_rules.json（可选）"),
        StepViewState(InstallStep.WRITE_ROUTING_RULES, "写入 routing_rules.json（可选）"),
        StepViewState(InstallStep.DOWNLOAD_RULE_SET, "下载 rule-set（可选）"),
        StepViewState(InstallStep.WRITE_RULE_SET, "写入 rule-set（可选）"),
        StepViewState(InstallStep.WRITE_CONFIG, "写入 config.json"),
        StepViewState(InstallStep.REGISTER_PROFILE, "注册到供应商列表"),
        StepViewState(InstallStep.FINALIZE, "完成"),
    )

    fun setOnCompletedListener(listener: () -> Unit) {
        onCompletedListener = listener
    }

    fun show() {
        val view = LayoutInflater.from(context)
            .inflate(R.layout.dialog_provider_install_wizard, null)

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
        val providerNameText = view.findViewById<TextView>(R.id.wizardProviderNameText)
        val selectSwitch = view.findViewById<SwitchCompat>(R.id.wizardSelectAfterInstallSwitch)
        val stepsContainer = view.findViewById<LinearLayout>(R.id.wizardStepsContainer)
        val errorText = view.findViewById<TextView>(R.id.wizardErrorText)
        val actionButton = view.findViewById<MaterialButton>(R.id.wizardActionButton)
        val runningContainer = view.findViewById<LinearLayout>(R.id.wizardRunningContainer)
        val runningText = view.findViewById<TextView>(R.id.wizardRunningText)
        val closeButton = view.findViewById<MaterialButton>(R.id.wizardCloseButton)

        // 设置供应商名字
        providerNameText.text = provider.name

        // 切换开关
        selectSwitch.isChecked = selectAfterInstall
        selectSwitch.setOnCheckedChangeListener { _, checked -> selectAfterInstall = checked }

        // 动态添加步骤行
        val inflater = LayoutInflater.from(context)
        stepStates.forEach { state ->
            val stepView = inflater.inflate(R.layout.item_install_step, stepsContainer, false)
            stepView.tag = state.step
            updateStepView(stepView, state)
            stepsContainer.addView(stepView)
        }

        // 按钮事件
        actionButton.setOnClickListener {
            when {
                isFinished -> {
                    onCompletedListener?.invoke()
                    dialog?.dismiss()
                }
                hasError -> {
                    // 重置并重试
                    hasError = false
                    errorText.visibility = View.GONE
                    stepStates.forEach { it.status = StepStatus.PENDING; it.message = null }
                    refreshAllStepViews(stepsContainer)
                    startInstall(stepsContainer, errorText, actionButton, runningContainer, runningText, closeButton, selectSwitch)
                }
                !isRunning -> {
                    startInstall(stepsContainer, errorText, actionButton, runningContainer, runningText, closeButton, selectSwitch)
                }
            }
        }

        closeButton.setOnClickListener {
            if (!isRunning) dialog?.dismiss()
        }

        updateFooter(actionButton, runningContainer, runningText, closeButton)
        dialog?.show()
    }

    private fun startInstall(
        stepsContainer: LinearLayout,
        errorText: TextView,
        actionButton: MaterialButton,
        runningContainer: LinearLayout,
        runningText: TextView,
        closeButton: MaterialButton,
        selectSwitch: SwitchCompat
    ) {
        isRunning = true
        updateFooter(actionButton, runningContainer, runningText, closeButton)
        selectSwitch.isEnabled = false

        MainScope().launch {
            val result = MarketInstaller.installProvider(
                context = context,
                provider = provider,
                selectAfterInstall = selectAfterInstall,
                onProgress = { progress ->
                    // 在主线程更新 UI
                    Handler(Looper.getMainLooper()).post {
                        handleProgress(progress, stepsContainer, runningText)
                    }
                }
            )
            // 回到主线程更新最终状态
            isRunning = false
            when (result) {
                is InstallResult.Success -> {
                    isFinished = true
                    // 最后一步设为 success
                    stepStates.find { it.step == InstallStep.FINALIZE }?.let { 
                        it.status = StepStatus.SUCCESS 
                        it.message = "完成"
                    }
                    refreshAllStepViews(stepsContainer)
                }
                is InstallResult.Failure -> {
                    hasError = true
                    errorText.text = "安装失败：${result.error}"
                    errorText.visibility = View.VISIBLE
                    // 将失败步骤标记为 FAILURE
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
        progress: InstallProgress,
        stepsContainer: LinearLayout,
        runningText: TextView
    ) {
        // 更新步骤状态
        val state = stepStates.find { it.step == progress.step } ?: return

        // 将上一个 RUNNING 步骤设为 SUCCESS
        stepStates.find { it.status == StepStatus.RUNNING && it.step != progress.step }
            ?.let { it.status = StepStatus.SUCCESS }

        state.status = StepStatus.RUNNING
        state.message = progress.message

        refreshAllStepViews(stepsContainer)
        runningText.text = progress.message
    }

    private fun refreshAllStepViews(stepsContainer: LinearLayout) {
        for (i in 0 until stepsContainer.childCount) {
            val view = stepsContainer.getChildAt(i)
            val step = view.tag as? InstallStep ?: continue
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
                actionButton.text = "完成"
                actionButton.isEnabled = true
                actionButton.backgroundTintList = ColorStateList.valueOf(
                    Color.parseColor("#1C87F5")
                )
                runningContainer.visibility = View.GONE
                closeButton.isEnabled = true
            }
            isRunning -> {
                actionButton.text = "安装中…"
                actionButton.isEnabled = false
                runningContainer.visibility = View.VISIBLE
                closeButton.isEnabled = false
            }
            hasError -> {
                actionButton.text = "重试"
                actionButton.isEnabled = true
                actionButton.backgroundTintList = ColorStateList.valueOf(
                    Color.parseColor("#1C87F5")
                )
                runningContainer.visibility = View.GONE
                closeButton.isEnabled = true
            }
            else -> {
                actionButton.text = "开始安装"
                actionButton.isEnabled = true
                actionButton.backgroundTintList = ColorStateList.valueOf(
                    Color.parseColor("#1C87F5")
                )
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
        StepStatus.RUNNING -> Color.parseColor("#1C87F5")
        StepStatus.SUCCESS -> Color.parseColor("#009E54")
        StepStatus.FAILURE -> Color.parseColor("#DE4A57")
    }
}
