allprojects {
    repositories {
        google()
        mavenCentral()
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
// Algunos plugins antiguos fijan su propio compileSdk (31 o 34). Forzamos
// API 36 en todos los módulos Android para que puedan usar dependencias
// AndroidX modernas sin fallar durante la comprobación de metadatos AAR.
subprojects {
    plugins.withId("com.android.application") {
        extensions.configure<com.android.build.api.dsl.ApplicationExtension> {
            compileSdk = 36
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.api.dsl.LibraryExtension> {
            compileSdk = 36
        }
    }
}

// Los scripts de algunos plugins asignan compileSdk después de aplicar el
// plugin Android. Esta segunda regla se ejecuta al terminar cada script y
// por eso prevalece sobre esos valores antiguos.
subprojects {
    afterEvaluate {
        extensions.findByType<com.android.build.api.dsl.ApplicationExtension>()
            ?.compileSdk = 36
        extensions.findByType<com.android.build.api.dsl.LibraryExtension>()
            ?.compileSdk = 36
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
