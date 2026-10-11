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
subprojects {
    project.evaluationDependsOn(":app")
}

// Workaround for old plugins (e.g. isar_flutter_libs) that don't
// declare a namespace (required by AGP 8+). Assign a fallback
// namespace so the build can proceed.
subprojects {
    afterEvaluate {
        plugins.withId("com.android.library") {
            try {
                val libExt = extensions.getByName("android")
                val getNs = libExt.javaClass.getMethod("getNamespace")
                if (getNs.invoke(libExt) == null) {
                    val setNs = libExt.javaClass.getMethod(
                        "setNamespace", String::class.java)
                    val fallback =
                        "com.puretube.plugin." +
                            project.name.replace(Regex("[^a-zA-Z0-9_]"), "_")
                    setNs.invoke(libExt, fallback)
                }
            } catch (_: Exception) {
                // Not an Android library or already handled.
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
