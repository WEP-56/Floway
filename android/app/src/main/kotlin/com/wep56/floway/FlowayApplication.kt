package com.wep56.floway

import android.app.Application
import android.content.Context
import com.wep56.floway.common.GlobalState

class FlowayApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        GlobalState.init(this)
    }
}
