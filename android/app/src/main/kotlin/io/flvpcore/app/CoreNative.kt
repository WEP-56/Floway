package io.flvpcore.app

object CoreNative {
    init { System.loadLibrary("flvp_host") }
    @JvmStatic external fun request(text: String): String
}
