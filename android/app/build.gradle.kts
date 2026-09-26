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
            // Firma con clave debug para compilación de prueba.
            // La distribución release tendrá su propio secreto, nunca en el repo.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
