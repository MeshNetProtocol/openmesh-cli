package com.meshnetprotocol.android

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Bundle
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import com.meshnetprotocol.android.vpn.OpenMeshVpnService
import com.meshnetprotocol.android.vpn.VpnServiceState
import com.meshnetprotocol.android.vpn.VpnStateMachine

class MainActivity : AppCompatActivity() {
    private lateinit var vpnStateText: TextView
    private lateinit var startVpnButton: MaterialButton
    private lateinit var stopVpnButton: MaterialButton

    private var receiverRegistered = false

    private val vpnPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        if (result.resultCode == RESULT_OK) {
            OpenMeshVpnService.start(this)
        } else {
            Toast.makeText(this, R.string.vpn_permission_denied, Toast.LENGTH_SHORT).show()
        }
    }

    private val vpnStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val stateName = intent?.getStringExtra(OpenMeshVpnService.EXTRA_STATE_NAME) ?: return
            val state = runCatching { VpnServiceState.valueOf(stateName) }.getOrNull() ?: return
            renderState(state)

            val errorMessage = intent.getStringExtra(OpenMeshVpnService.EXTRA_ERROR_MESSAGE)
            if (!errorMessage.isNullOrBlank()) {
                Toast.makeText(this@MainActivity, errorMessage, Toast.LENGTH_LONG).show()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        vpnStateText = findViewById(R.id.vpnStateText)
        startVpnButton = findViewById(R.id.startVpnButton)
        stopVpnButton = findViewById(R.id.stopVpnButton)

        startVpnButton.setOnClickListener { requestVpnPermissionAndStart() }
        stopVpnButton.setOnClickListener { OpenMeshVpnService.stop(this) }

        renderState(VpnStateMachine.currentState())
    }

    override fun onStart() {
        super.onStart()
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                this,
                vpnStateReceiver,
                IntentFilter(OpenMeshVpnService.ACTION_STATE_CHANGED),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiverRegistered = true
        }
        renderState(VpnStateMachine.currentState())
    }

    override fun onStop() {
        if (receiverRegistered) {
            unregisterReceiver(vpnStateReceiver)
            receiverRegistered = false
        }
        super.onStop()
    }

    private fun requestVpnPermissionAndStart() {
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent != null) {
            vpnPermissionLauncher.launch(prepareIntent)
            return
        }
        OpenMeshVpnService.start(this)
    }

    private fun renderState(state: VpnServiceState) {
        vpnStateText.text = when (state) {
            VpnServiceState.STOPPED -> getString(R.string.vpn_state_stopped)
            VpnServiceState.STARTING -> getString(R.string.vpn_state_starting)
            VpnServiceState.STARTED -> getString(R.string.vpn_state_started)
            VpnServiceState.STOPPING -> getString(R.string.vpn_state_stopping)
        }

        startVpnButton.isEnabled = state == VpnServiceState.STOPPED
        stopVpnButton.isEnabled = state == VpnServiceState.STARTED || state == VpnServiceState.STARTING
    }
}
