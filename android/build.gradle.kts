// Top-level project build.gradle.kts
plugins {
    // Kotlin Gradle plugin
    kotlin("android") version "2.0.21" apply false
    // Android Gradle plugin
    id("com.android.application") version "8.2.0" apply false
    // Flutter Gradle plugin
    id("dev.flutter.flutter-gradle-plugin") version "0.1.15" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
