import java.util.Properties

// Firma de distribución: android/key.properties (gitignoreado) apunta al
// keystore real. Sin él se cae a clave debug (solo para pruebas locales).
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(f.inputStream())
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.bermes.hermes_pocket"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "dev.bermes.hermes_pocket"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // El doNotStrip acelera builds de DEBUG (evita el task stripDebugSymbols,
            // lento en CI), pero DEBE quedar limitado a debug: sin él, libflutter.so
            // ship 154MB de secciones .debug_* y el APK pasa de ~20MB a 184MB.
            // En release sí se hace strip (AGP lo aplica salvo doNotStrip).
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.create("release").apply {
                    storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                    // v1+v2+v3: máximo de compatibilidad de instalación
                    // (v1 cubre ROMs/gestores antiguos; v2/v3, Android 7+).
                    enableV1Signing = true
                    enableV2Signing = true
                    enableV3Signing = true
                }
            } else {
                // Sin key.properties: firma debug (build de prueba).
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
