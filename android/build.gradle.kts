import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

subprojects {
    // Keep each plugin module's Kotlin target aligned with its matching Java
    // compile task. Some Flutter plugins still declare Java 1.8/11 while newer
    // Kotlin Gradle defaults can jump higher, which breaks Android builds with
    // "Inconsistent JVM Target Compatibility" errors.
    tasks.withType<KotlinCompile>().configureEach {
        val javaTask = project.tasks.findByName(name.replace("Kotlin", "JavaWithJavac"))
        val javaTarget = javaTask
            ?.let { task -> task.javaClass.methods.firstOrNull { method -> method.name == "getTargetCompatibility" }?.invoke(task) as? String }
            ?.trim()

        compilerOptions {
            jvmTarget.set(
                when (javaTarget) {
                    JavaVersion.VERSION_1_8.toString(), "1.8" -> JvmTarget.JVM_1_8
                    JavaVersion.VERSION_11.toString(), "11" -> JvmTarget.JVM_11
                    JavaVersion.VERSION_17.toString(), "17" -> JvmTarget.JVM_17
                    JavaVersion.VERSION_21.toString(), "21" -> JvmTarget.JVM_21
                    else -> JvmTarget.JVM_17
                },
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
