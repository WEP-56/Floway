package com.wep56.floway.service.models

data class NotificationParams(
    val title: String = "Floway",
    val stopText: String = "STOP",
    val onlyStatisticsProxy: Boolean = false,
    val showStopAction: Boolean = true,
)
