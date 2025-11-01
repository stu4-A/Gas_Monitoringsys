pluginManagement {
    repositories {
        gradlePluginPortal()
        google()
        mavenCentral()
    }

    plugins {
        id("com.android.application") version "8.2.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
    }
}

rootProject.name = "gasmonitoringsys"
include(":app")
