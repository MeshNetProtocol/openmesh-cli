package com.meshnetprotocol.android.vpn

object VpnStateMachine {
    private val lock = Any()

    @Volatile
    private var state: VpnServiceState = VpnServiceState.STOPPED

    fun currentState(): VpnServiceState = state

    fun transitionTo(next: VpnServiceState): Boolean {
        synchronized(lock) {
            if (!isValidTransition(state, next)) {
                return false
            }
            state = next
            return true
        }
    }

    fun forceState(next: VpnServiceState) {
        synchronized(lock) {
            state = next
        }
    }

    private fun isValidTransition(from: VpnServiceState, to: VpnServiceState): Boolean {
        if (from == to) {
            return true
        }
        return when (from) {
            VpnServiceState.STOPPED -> to == VpnServiceState.STARTING
            VpnServiceState.STARTING -> to == VpnServiceState.STARTED || to == VpnServiceState.STOPPING || to == VpnServiceState.STOPPED
            VpnServiceState.STARTED -> to == VpnServiceState.STOPPING
            VpnServiceState.STOPPING -> to == VpnServiceState.STOPPED
        }
    }
}
