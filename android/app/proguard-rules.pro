# 腾讯定位 SDK 的 native 层会通过 JNI/反射按原始类名查找部分类。
# Flutter release 构建会走 R8 压缩，若这些类被移除或改名，启动定位时会闪退。
-keep class com.tencent.map.geolocation.** { *; }
-keep class com.tencent.tencentmap.** { *; }
-keep class c.t.m.g.** { *; }

-dontwarn com.tencent.map.geolocation.**
-dontwarn com.tencent.tencentmap.**
-dontwarn c.t.m.g.**
