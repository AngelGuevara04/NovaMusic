allprojects {
    repositories {
        google()
        mavenCentral()
        // --- SERVIDOR ESPEJO COMUNITARIO PARA FFMPEG-KIT 6.0-2 ---
        maven { url = uri("https://raw.githubusercontent.com/DucLQ92/ffmpeg-kit-audio/main") }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    afterEvaluate {
        project.extensions.findByName("android")?.let { androidExt ->
            try {
                androidExt.javaClass.getMethod("setCompileSdk", Int::class.java).invoke(androidExt, 36)
            } catch (e: Exception) {
                try {
                    androidExt.javaClass.getMethod("setCompileSdkVersion", Int::class.java).invoke(androidExt, 36)
                } catch (e2: Exception) {}
            }
        }
    }

    if (project.name != "file_picker") {
        afterEvaluate {
            project.extensions.findByName("android")?.let { androidExt ->
                try {
                    val compileOptions = androidExt.javaClass.getMethod("getCompileOptions").invoke(androidExt)
                    compileOptions.javaClass.getMethod("setSourceCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                    compileOptions.javaClass.getMethod("setTargetCompatibility", JavaVersion::class.java).invoke(compileOptions, JavaVersion.VERSION_17)
                } catch (e: Exception) {}
            }
        }

        tasks.configureEach {
            if (name.startsWith("compile") && name.endsWith("Kotlin")) {
                try {
                    val kotlinOptions = javaClass.getMethod("getKotlinOptions").invoke(this)
                    kotlinOptions.javaClass.getMethod("setJvmTarget", String::class.java).invoke(kotlinOptions, "17")
                } catch (e: Exception) {}
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
