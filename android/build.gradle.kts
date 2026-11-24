allprojects {
    repositories {
        google()
        mavenCentral()
        maven("https://developer.huawei.com/repo/") {
            content { includeGroupByRegex("com[.]huawei[.].*") }
        }
        maven("https://developer.hihonor.com/repo/") {
            content { includeGroup("com.hihonor.mcs") }
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
