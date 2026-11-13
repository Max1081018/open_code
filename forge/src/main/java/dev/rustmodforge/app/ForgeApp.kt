package dev.rustmodforge.app

import android.app.Application
import dev.rustmodforge.app.data.SettingsStore
import java.io.File

class ForgeApp : Application() {
    lateinit var settings: SettingsStore
        private set

    /** Every conversion project lives here, one folder each (see core `Project`). */
    val projectsRoot: File get() = File(filesDir, "projects").apply { mkdirs() }

    override fun onCreate() {
        super.onCreate()
        settings = SettingsStore(this)
    }
}
