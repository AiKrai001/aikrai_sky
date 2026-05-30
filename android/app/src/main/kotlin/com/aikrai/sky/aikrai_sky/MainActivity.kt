package com.aikrai.sky.aikrai_sky

import android.os.Looper
import android.provider.Settings
import android.util.Log
import com.tencent.map.geolocation.TencentLocation
import com.tencent.map.geolocation.TencentLocationListener
import com.tencent.map.geolocation.TencentLocationManager
import com.tencent.map.geolocation.TencentLocationManagerOptions
import com.tencent.map.geolocation.TencentLocationRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val tencentLocationChannelName = "aikrai_sky/tencent_location"
    private var pendingLocationResult: MethodChannel.Result? = null

    companion object {
        private const val locationLogTag = "AiKraiSkyLocation"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            tencentLocationChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestCurrentLocation" -> requestCurrentLocation(call, result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requestCurrentLocation(call: MethodCall, result: MethodChannel.Result) {
        if (pendingLocationResult != null) {
            result.error("ALREADY_RUNNING", "Tencent location request is already running.", null)
            return
        }

        val key = call.argument<String>("key")?.trim().orEmpty()
        if (key.isEmpty()) {
            result.error("MISSING_KEY", "Tencent map key is required.", null)
            return
        }

        pendingLocationResult = result

        try {
            Log.d(locationLogTag, "Tencent location request start.")
            // SDK 要求在初始化 TencentLocationManager 前完成隐私合规和 Key 设置。
            TencentLocationManager.setUserAgreePrivacy(true)
            TencentLocationManagerOptions.setKey(key)

            val manager = TencentLocationManager.getInstance(applicationContext)
            manager.setDeviceID(applicationContext, resolveDeviceId())
            val request =
                TencentLocationRequest.create().apply {
                    setRequestLevel(TencentLocationRequest.REQUEST_LEVEL_ADMIN_AREA)
                    // 天气首页需要稳定拿到行政区划。真机上 GPS 首点可能只有经纬度，
                    // 因此这里优先使用网络定位，并等待首个定位点补齐地址信息。
                    setLocMode(TencentLocationRequest.ONLY_NETWORK_MODE)
                    setAllowGPS(false)
                    setAllowCache(false)
                    setFirstLocationNeedAddress(true)
                    setLocFirstTimeOut(10_000L)
                }
            val listener =
                object : TencentLocationListener {
                    override fun onLocationChanged(
                        location: TencentLocation?,
                        error: Int,
                        reason: String?,
                    ) {
                        val currentResult = pendingLocationResult ?: return
                        pendingLocationResult = null

                        if (error != TencentLocation.ERROR_OK || location == null) {
                            Log.e(
                                locationLogTag,
                                "Tencent location failed. error=$error, reason=$reason",
                            )
                            currentResult.error(
                                "TENCENT_LOCATION_ERROR",
                                reason ?: "Tencent location failed: $error",
                                error,
                            )
                            return
                        }

                        val locationMap = location.toFlutterMap()
                        Log.d(locationLogTag, "Tencent raw location: $locationMap")
                        currentResult.success(locationMap)
                    }

                    override fun onStatusUpdate(name: String?, status: Int, desc: String?) {
                        Log.d(
                            locationLogTag,
                            "Tencent location status. name=$name, status=$status, desc=$desc",
                        )
                    }
                }

            val requestCode = manager.requestSingleFreshLocation(
                request,
                listener,
                Looper.getMainLooper(),
            )
            Log.d(
                locationLogTag,
                "Tencent location request code=$requestCode, " +
                    "requestLevel=${request.requestLevel}, " +
                    "locMode=${request.locMode}, allowGps=${request.isAllowGPS}, " +
                    "allowCache=${request.isAllowCache}, " +
                    "firstNeedAddress=${request.isFirstLocationNeedAddress}",
            )
        } catch (error: Throwable) {
            pendingLocationResult = null
            Log.e(locationLogTag, "Tencent location exception.", error)
            result.error(
                "TENCENT_LOCATION_EXCEPTION",
                error.message ?: "Tencent location request failed.",
                null,
            )
        }
    }

    private fun resolveDeviceId(): String {
        val rawId =
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                ?: "aikrai_sky"
        val normalizedId = rawId.replace(Regex("[^A-Za-z0-9_]"), "_")
        return normalizedId.ifEmpty { "aikrai_sky" }
    }

    private fun TencentLocation.toFlutterMap(): Map<String, Any?> =
        mapOf(
            "latitude" to latitude,
            "longitude" to longitude,
            "altitude" to altitude,
            "accuracy" to accuracy,
            "nation" to nation,
            "province" to province,
            "city" to city,
            "district" to district,
            "town" to town,
            "village" to village,
            "street" to street,
            "streetNo" to streetNo,
            "name" to name,
            "address" to address,
            "adCode" to cityCode,
            "cityCode" to cityCode,
            "cityPhoneCode" to cityPhoneCode,
        )
}
