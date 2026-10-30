package io.flvpcore.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

class ProxyService : Service() {
    companion object {
        var current: ProxyService? = null
            private set
        private const val CHANNEL = "ordinary-proxy"
        private const val ID = 1001
    }
    private var epoch = 0L
    private var requestVersion = 0L

    override fun onCreate() {
        super.onCreate()
        current = this
        epoch = CoreRuntime.serviceCreated()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL, "本地代理", NotificationManager.IMPORTANCE_LOW))
        val notification = notification("正在启动本地代理…")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else startForeground(ID, notification)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            requestVersion = CoreRuntime.stopOwned(applicationContext)
        } else {
            val text = intent?.getStringExtra("request")
            val token = intent?.getStringExtra("token")
            requestVersion = intent?.getLongExtra("version", 0L) ?: 0L
            if (text != null && token != null) CoreRuntime.fromService(this, text, token, requestVersion)
            else stopSelf()
        }
        // Never reconnect without an explicit user action after process death.
        return START_NOT_STICKY
    }

    fun showRunning(port: Int) {
        getSystemService(NotificationManager::class.java).notify(ID,
            notification("127.0.0.1:$port · HTTP / SOCKS5"))
    }

    private fun notification(text: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1,
            Intent(this, ProxyService::class.java).setAction("STOP"),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL).setContentTitle("FLVPcore · 本地代理")
            .setContentText(text).setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "停止", stop).build()).build()
    }

    override fun onDestroy() {
        if (current === this) current = null
        CoreRuntime.stopOwned(applicationContext, epoch, requestVersion)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
