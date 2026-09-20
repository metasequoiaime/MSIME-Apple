// The native host's own Gradle build, separate from the Tauri bundle's generated project: that one
// exists to wrap a WebView, this one only needs AndroidX and Material. Versions are pinned to the
// same values the bundle resolves, so one machine fetches one set of artifacts.
pluginManagement {
    repositories { google(); mavenCentral() }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "msime-android-host"
include(":app")
