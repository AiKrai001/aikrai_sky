import java.awt.RenderingHints
import java.awt.image.BufferedImage
import java.net.URI
import javax.imageio.ImageIO
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aikrai.sky.aikrai_sky"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aikrai.sky.aikrai_sky"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.tencent.map.geolocation:TencentLocationSdk-openplatform:7.6.1.8")
}

// 打包前根据用户指定图片链接生成 Android 启动图标，避免手动维护多套 mipmap 尺寸。
val generateAikraiLauncherIcons by tasks.registering {
    val sourceIconUrl = "https://pixel-oss.aikrai.com/picgo/8e333d16a90f1e110f3350977ac55a3a.png"
    val iconSizes =
        mapOf(
            "mipmap-mdpi" to 48,
            "mipmap-hdpi" to 72,
            "mipmap-xhdpi" to 96,
            "mipmap-xxhdpi" to 144,
            "mipmap-xxxhdpi" to 192,
        )

    inputs.property("sourceIconUrl", sourceIconUrl)
    outputs.files(
        iconSizes.keys.map { density ->
            layout.projectDirectory.file("src/main/res/$density/ic_launcher.png")
        },
    )
    // 远程图片内容可能在 URL 不变时更新，每次构建都重新生成一次，保证打包图标是最新链接内容。
    outputs.upToDateWhen { false }

    doLast {
        val sourceImage =
            URI(sourceIconUrl).toURL().openConnection().apply {
                connectTimeout = 15000
                readTimeout = 15000
                setRequestProperty("User-Agent", "AiKraiSky Gradle Icon Generator")
            }.getInputStream().use { stream ->
                ImageIO.read(stream)
            } ?: throw GradleException("Launcher icon source cannot be decoded: $sourceIconUrl")

        iconSizes.forEach { (density, size) ->
            val outputFile = layout.projectDirectory.file("src/main/res/$density/ic_launcher.png").asFile
            outputFile.parentFile.mkdirs()

            val scale = maxOf(size.toDouble() / sourceImage.width, size.toDouble() / sourceImage.height)
            val drawWidth = Math.ceil(sourceImage.width * scale).toInt()
            val drawHeight = Math.ceil(sourceImage.height * scale).toInt()
            val offsetX = Math.floor((size - drawWidth) / 2.0).toInt()
            val offsetY = Math.floor((size - drawHeight) / 2.0).toInt()
            val launcherIcon = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
            val graphics = launcherIcon.createGraphics()

            try {
                graphics.setRenderingHint(
                    RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BICUBIC,
                )
                graphics.setRenderingHint(
                    RenderingHints.KEY_RENDERING,
                    RenderingHints.VALUE_RENDER_QUALITY,
                )
                graphics.setRenderingHint(
                    RenderingHints.KEY_ANTIALIASING,
                    RenderingHints.VALUE_ANTIALIAS_ON,
                )
                graphics.drawImage(sourceImage, offsetX, offsetY, drawWidth, drawHeight, null)
                ImageIO.write(launcherIcon, "png", outputFile)
            } finally {
                graphics.dispose()
            }
        }
    }
}

tasks.configureEach {
    if (name == "preBuild") {
        dependsOn(generateAikraiLauncherIcons)
    }
}
