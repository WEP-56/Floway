package com.wep56.floway.service

import android.app.Service
import android.content.ComponentCallbacks2
import com.wep56.floway.common.BroadcastAction
import com.wep56.floway.common.GlobalState
import com.wep56.floway.common.sendBroadcast
import com.wep56.floway.core.Core

interface ManagedService {
    fun start()

    fun stop()
}

internal fun Service.notifyVpnStartRequested() {
    GlobalState.log("VPN start requested")
    BroadcastAction.VPN_START_REQUESTED.sendBroadcast()
}

internal fun Service.notifyVpnRevoked() {
    GlobalState.log("VPN permission revoked")
    BroadcastAction.VPN_REVOKED.sendBroadcast()
}

// UI_HIDDEN reaches the services too, since they share the activity's process,
// and Android 14 stopped delivering the running levels this answers to.
@Suppress("DEPRECATION")
internal fun trimCoreMemory(level: Int) {
    if (level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
        level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL
    ) {
        Core.forceGC()
    }
}
