allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // Text recognition: use the Google Play services variant, whose model
    // is downloaded on demand, instead of bundling about 30 MB in the APK.
    configurations.all {
        resolutionStrategy.dependencySubstitution {
            substitute(module("com.google.mlkit:text-recognition"))
                .using(module("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1"))
        }
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
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
