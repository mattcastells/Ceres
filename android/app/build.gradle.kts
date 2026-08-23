import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. Las credenciales viven en android/key.properties, que está
// fuera del control de versiones; el keystore es android/ceres-upload.jks.
// Si el archivo no está, el release cae a la firma de debug para que
// `flutter run --release` siga andando en una máquina sin las claves.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseSigning = keystoreProperties.getProperty("storeFile") != null &&
    rootProject.file(keystoreProperties.getProperty("storeFile") ?: "").exists()

android {
    namespace = "io.ceres.ceres"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // `flutter_local_notifications` usa java.time, que no existe antes de
        // API 26. El desugaring lo traduce; se deja prendido aunque el `minSdk`
        // ya sea 26 porque otras dependencias pueden traer APIs más nuevas, y
        // apagarlo solo se nota cuando una explota en un teléfono viejo.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "io.ceres.app"
        // 26 lo pide `androidx.health.connect:connect-client`, que es lo que
        // trae los datos de Samsung Health y de Zepp (D-21). Antes era 24; subir
        // deja afuera Android 7.0 y 7.1, que es de 2016 y no está en ningún
        // teléfono en uso de los que conocemos.
        //
        // Ojo: 26 es el piso para **compilar**. Health Connect en sí necesita
        // Android 9 para instalarse como app aparte, y desde Android 14 viene en
        // el sistema. `HealthConnectBridge.availability` distingue los tres
        // casos, porque "tu Android no lo soporta" y "instalá Health Connect" se
        // arreglan de formas distintas.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

// ⚠️ No compilar con `--split-per-abi` mientras el updater baje un solo APK.
//
// Con esa opción el plugin de Flutter le suma a cada APK un corrimiento por
// arquitectura (`abi * 1000 + versionCode`): el universal queda en 11 y el de
// arm64 en 2011. Como el updater baja **siempre el universal**, quien había
// instalado el de su arquitectura recibía la actualización, la descargaba, y
// Android la rechazaba por downgrade (2011 → 12). El síntoma es "No se
// instaló la app", sin explicación, y no hay salida más que desinstalar —
// perdiendo los datos locales.
//
// Se intentó anular el corrimiento desde acá con `androidComponents
// .onVariants { output.versionCode.set(...) }` y **no alcanza**: el plugin lo
// pisa con la API vieja (`versionCodeOverride`) en su `afterEvaluate`, que
// corre después. Verificado con `aapt2 dump badging`: seguía dando 6000 /
// 7000 / 9000. Por eso el release publica un único APK universal en vez de
// pelearle al orden de los callbacks, y `release.yml` verifica el
// versionCode de lo que publica.

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // `FileProvider`, para entregarle el APK de la actualización al instalador
    // de paquetes como `content://`. Va explícita y no de arrastre: lo que
    // llega transitivamente de un AAR no queda en el classpath de compilación.
    implementation("androidx.core:core-ktx:1.13.1")
    // Health Connect: el almacén de datos de salud del teléfono. Samsung Health
    // y el Zepp app escriben ahí, así que con esta sola integración llegan los
    // datos de los relojes Samsung y de los Amazfit — Zepp no tiene API pública
    // para leerle nada, pero sí sincroniza hacia Health Connect.
    //
    // **1.1.0 estable, no la alpha.** Estuvo en `1.1.0-alpha07` desde que se
    // sumó la integración: una alpha en el build que se publica es firmar un
    // contrato que el proveedor puede cambiar sin aviso, y acá el que la paga
    // es alguien cuyo peso no importa. La API que usa `HealthConnectBridge`
    // —`readRecords`, `WeightRecord`, `BodyFatRecord`, `SleepSessionRecord`— es
    // la misma en las dos.
    implementation("androidx.health.connect:connect-client:1.1.0")
    // Corrutinas: `connect-client` es `suspend` de punta a punta. Va explícita
    // porque lo que llega transitivamente de un AAR no queda en el classpath.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}
