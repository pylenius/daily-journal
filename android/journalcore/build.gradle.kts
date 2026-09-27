plugins {
    alias(libs.plugins.kotlin.jvm)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    testImplementation(kotlin("test"))
    testImplementation(libs.junit.jupiter)
    testRuntimeOnly(libs.junit.launcher)
}

tasks.test {
    useJUnitPlatform()
    // One copy of the fixtures, shared with the Swift and C# tests.
    val fixtures = rootDir.resolve("../ios/Packages/JournalKit/Tests/JournalKitTests/Fixtures")
    inputs.dir(fixtures)
    systemProperty("journal.fixtures", fixtures.absolutePath)
}
