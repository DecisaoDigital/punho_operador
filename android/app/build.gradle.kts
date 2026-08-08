import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "pt.decisaodigital.punho_operador"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "pt.decisaodigital.punho_operador"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // O arnês que deixa correr os testes de integração por `am instrument`,
        // sem passar pelo `flutter test`. A diferença não é de gosto: o
        // `flutter test` desinstala a app quando acaba, e no MIUI cada
        // instalação de raiz volta a exigir um toque humano numa caixa que
        // expira sozinha. Por aqui instala-se uma vez e daí para a frente é
        // sempre actualização por cima — que passa livre, porque a chave de
        // debug é sempre a mesma.
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // A chave de release do Punho OP. É diferente da do Punho de propósito:
    // são dois APKs com identidades Android distintas, e o Control e o Punho
    // já seguem esta regra de uma chave por app.
    //
    // A chave é permanente. O Android identifica uma app pelo par
    // (applicationId, certificado): trocá-la mais tarde obriga toda a gente a
    // desinstalar antes de actualizar. Perder o ficheiro ou a senha tem o
    // mesmo efeito, e não há como recuperá-los.
    signingConfigs {
        create("release") {
            check(keystorePropertiesFile.exists()) {
                "Falta android/key.properties. Um APK release do Punho OP tem " +
                    "de ser assinado com a chave de release."
            }
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }

    buildTypes {
        release {
            // Nunca publicar uma release assinada pela chave de depuração: ela
            // é gerada por máquina, muda sem aviso, e uma app publicada com
            // ela fica sem forma de ser actualizada.
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // O ficheiro sai com o nome e a versão em vez de "app-release.apk", como
    // no Punho: o que se instala por USB diz-se a si próprio.
    @Suppress("DEPRECATION")
    applicationVariants.all {
        val versao = versionName
        outputs.all {
            val saida =
                this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            if (saida.outputFileName.endsWith("-release.apk")) {
                saida.outputFileName = "PunhoOP_v$versao.apk"
            }
        }
    }
}

dependencies {
    // Presas ao 1.3.0 de propósito: é a versão que o plugin `integration_test`
    // já põe no classpath da app, e o Gradle exige que o arnês use a mesma.
    // Pedir uma mais recente rebenta a compilação com "consistent resolution".
    androidTestImplementation("androidx.test:runner:1.3.0")
    androidTestImplementation("androidx.test:rules:1.2.0")
    androidTestImplementation("junit:junit:4.12")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
