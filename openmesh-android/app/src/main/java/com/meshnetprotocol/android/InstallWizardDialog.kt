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
import com.meshnetprotocol.android.vpn.OpenMeshRoutingRuleInjector
import org.json.JSONObject

/**
 * Offline import installer aligned with the iOS/Windows provider layout.
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
        StepState(StepID.FETCH_DETAIL, "Read provider details", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_CONFIG, "Load config payload", StepStatus.PENDING),
        StepState(StepID.VALIDATE_CONFIG, "Validate config", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_ROUTING_RULES, "Load routing rules", StepStatus.PENDING),
        StepState(StepID.WRITE_ROUTING_RULES, "Write routing_rules.json", StepStatus.PENDING),
        StepState(StepID.DOWNLOAD_RULE_SET, "Collect rule-set metadata", StepStatus.PENDING),
        StepState(StepID.WRITE_RULE_SET, "Keep native rule-set mode", StepStatus.PENDING),
        StepState(StepID.WRITE_CONFIG, "Write config.json", StepStatus.PENDING),
        StepState(StepID.REGISTER_PROFILE, "Register selected profile", StepStatus.PENDING),
        StepState(StepID.FINALIZE, "Finish", StepStatus.PENDING),
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

        val providerNameText = view.findViewById<TextView>(R.id.providerNameText)
        val selectSwitch = view.findViewById<SwitchCompat>(R.id.selectAfterInstallSwitch)
        val stepsContainer = view.findViewById<LinearLayout>(R.id.stepsContainer)
        val closeButton = view.findViewById<MaterialButton>(R.id.closeButton)
        val actionButton = view.findViewById<MaterialButton>(R.id.actionButton)
        val runningContainer = view.findViewById<LinearLayout>(R.id.runningContainer)
        val runningText = view.findViewById<TextView>(R.id.runningText)

        providerNameText.text = providerName
        selectSwitch.isChecked = selectAfterInstall
        selectSwitch.setOnCheckedChangeListener { _, isChecked -> selectAfterInstall = isChecked }

        steps.forEach { step ->
            val stepView = LayoutInflater.from(context).inflate(R.layout.item_install_step, stepsContainer, false)
            stepView.findViewById<TextView>(R.id.stepStatusIcon).text = getStatusIcon(step.status)
            stepView.findViewById<TextView>(R.id.stepTitleText).text = step.title
            stepView.tag = step.id
            stepsContainer.addView(stepView)
        }

        closeButton.setOnClickListener {
            if (!isRunning) dialog?.dismiss()
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
            if (index == 0) {
                step.status = StepStatus.RUNNING
                view.findViewById<TextView>(R.id.stepStatusIcon).text = getStatusIcon(StepStatus.RUNNING)
                view.findViewById<TextView>(R.id.stepMessageText).apply {
                    text = "Starting install..."
                    visibility = View.VISIBLE
                }
            }
        }
        executeInstall()
    }

    private fun executeInstall() {
        Thread {
            try {
                updateStepStatus(StepID.FETCH_DETAIL, StepStatus.RUNNING, "Prepare provider metadata")
                Thread.sleep(120)
                updateStepStatus(StepID.FETCH_DETAIL, StepStatus.SUCCESS, "Done")

                updateStepStatus(StepID.DOWNLOAD_CONFIG, StepStatus.RUNNING, "Read imported payload")
                Thread.sleep(120)
                updateStepStatus(StepID.DOWNLOAD_CONFIG, StepStatus.SUCCESS, "Done")

                updateStepStatus(StepID.VALIDATE_CONFIG, StepStatus.RUNNING, "Validate provider config")
                val rawConfigJson = String(payload.configData, Charsets.UTF_8).trim()
                if (rawConfigJson.isEmpty()) {
                    throw IllegalStateException("Imported config is empty")
                }
                JSONObject(rawConfigJson)
                updateStepStatus(StepID.VALIDATE_CONFIG, StepStatus.SUCCESS, "Done")

                updateStepStatus(StepID.DOWNLOAD_ROUTING_RULES, StepStatus.SUCCESS, "Imported payload")
                val rulesData = payload.routingRulesData
                if (rulesData != null && rulesData.isNotEmpty()) {
                    val routingRulesJson = String(rulesData, Charsets.UTF_8).trim()
                    val injectableRuleCount = OpenMeshRoutingRuleInjector.countInjectableRules(routingRulesJson)
                    if (injectableRuleCount > 0) {
                        updateStepStatus(
                            StepID.WRITE_ROUTING_RULES,
                            StepStatus.RUNNING,
                            "Persist routing_rules.json ($injectableRuleCount rules)"
                        )
                        storageManager.writeRoutingRules(providerID, routingRulesJson).onFailure { throw it }
                        updateStepStatus(StepID.WRITE_ROUTING_RULES, StepStatus.SUCCESS, "Done")
                    } else {
                        Log.w(
                            TAG,
                            "install: skip overwriting routing_rules.json because imported rules produced 0 injectable proxy rule(s)"
                        )
                        updateStepStatus(StepID.WRITE_ROUTING_RULES, StepStatus.SUCCESS, "Skipped")
                    }
                } else {
                    updateStepStatus(StepID.WRITE_ROUTING_RULES, StepStatus.SUCCESS, "Skipped")
                }

                updateStepStatus(StepID.DOWNLOAD_RULE_SET, StepStatus.SUCCESS, "Use sing-box native remote updates")
                updateStepStatus(StepID.WRITE_RULE_SET, StepStatus.SUCCESS, "No local .srs written")

                updateStepStatus(StepID.WRITE_CONFIG, StepStatus.RUNNING, "Persist config snapshot")
                storageManager.writeFullConfig(providerID, rawConfigJson).onFailure { throw it }
                val result = storageManager.writeConfig(providerID, rawConfigJson)
                result.onFailure { throw it }
                updateStepStatus(StepID.WRITE_CONFIG, StepStatus.SUCCESS, "Done")

                updateStepStatus(StepID.REGISTER_PROFILE, StepStatus.RUNNING, "Select installed profile")
                val configFile = result.getOrNull() ?: error("config.json write failed")
                context.getSharedPreferences(ProfileRepository.PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putLong(ProfileRepository.KEY_SELECTED_PROFILE_ID, System.currentTimeMillis())
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_NAME, providerName)
                    .putString(ProfileRepository.KEY_SELECTED_PROFILE_PATH, configFile.absolutePath)
                    .putString(ProfileRepository.KEY_SELECTED_PROVIDER_ID, providerID)
                    .apply()
                // Persist friendly name for UI display
                com.meshnetprotocol.android.market.ProviderPreferences
                    .saveProviderName(context, providerID, providerName)

                updateStepStatus(StepID.REGISTER_PROFILE, StepStatus.SUCCESS, "Done")

                updateStepStatus(StepID.FINALIZE, StepStatus.SUCCESS, "Done")
                isRunning = false
                isFinished = true

                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    dialog?.findViewById<MaterialButton>(R.id.actionButton)?.let { button ->
                        button.text = "Done"
                    }
                    dialog?.findViewById<LinearLayout>(R.id.runningContainer)?.visibility = View.GONE
                }

                Log.i(TAG, "install completed: provider=$providerID name=$providerName")
            } catch (e: Exception) {
                isRunning = false
                Log.e(TAG, "install failed: ${e.message}", e)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    dialog?.findViewById<TextView>(R.id.errorText)?.let { errorText ->
                        errorText.text = "Install failed: ${e.message}"
                        errorText.visibility = View.VISIBLE
                    }
                }
            }
        }.start()
    }

    private fun updateStepStatus(stepID: StepID, status: StepStatus, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            val container = dialog?.findViewById<LinearLayout>(R.id.stepsContainer) ?: return@post
            for (i in 0 until container.childCount) {
                val view = container.getChildAt(i)
                if (view.tag != stepID) continue
                steps.find { it.id == stepID }?.status = status
                view.findViewById<TextView>(R.id.stepStatusIcon).text = getStatusIcon(status)
                view.findViewById<TextView>(R.id.stepMessageText).apply {
                    text = message
                    visibility = View.VISIBLE
                }
                break
            }
        }
    }

    private fun updateSteps(updateFn: (View, Int, StepState) -> Unit) {
        val container = dialog?.findViewById<LinearLayout>(R.id.stepsContainer) ?: return
        for (i in 0 until container.childCount) {
            if (i < steps.size) updateFn(container.getChildAt(i), i, steps[i])
        }
    }

    private fun updateActionButton(
        button: MaterialButton,
        runningContainer: LinearLayout,
        runningText: TextView
    ) {
        when {
            isFinished -> {
                button.text = "Done"
                button.isEnabled = true
                runningContainer.visibility = View.GONE
            }
            isRunning -> {
                button.text = "Installing..."
                button.isEnabled = false
                runningContainer.visibility = View.VISIBLE
                runningText.text = "Applying provider files..."
            }
            else -> {
                button.text = "Start Install"
                button.isEnabled = true
                runningContainer.visibility = View.GONE
            }
        }
    }

    private fun getStatusIcon(status: StepStatus): String {
        return when (status) {
            StepStatus.PENDING -> "○"
            StepStatus.RUNNING -> "◔"
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
        FINALIZE,
    }

    data class StepState(
        val id: StepID,
        val title: String,
        var status: StepStatus,
        var message: String? = null,
    )

    enum class StepStatus {
        PENDING,
        RUNNING,
        SUCCESS,
        FAILURE,
    }

    companion object {
        private const val TAG = "InstallWizardDialog"
    }
}
