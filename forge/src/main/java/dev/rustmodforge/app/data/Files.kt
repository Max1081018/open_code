package dev.rustmodforge.app.data

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.IOException

/** Copies files the user picked (Storage Access Framework) into the app's own storage. */
object Imports {
    const val MAX_IMPORT_BYTES = 512L shl 20

    fun displayName(context: Context, uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) c.getString(0)?.let { return it }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "mod.jar"
    }

    /**
     * Streams [uri] into [dir], refusing anything over [MAX_IMPORT_BYTES] or that is not a zip
     * (jar) archive. The original file is only read, never changed.
     */
    fun copyIn(context: Context, uri: Uri, dir: File): File {
        dir.mkdirs()
        val name = displayName(context, uri).replace(Regex("[^A-Za-z0-9._+-]"), "_").ifBlank { "mod.jar" }
        val out = File(dir, name)
        val input = context.contentResolver.openInputStream(uri) ?: throw IOException("cannot open $name")
        input.use { i ->
            out.outputStream().use { o ->
                val buf = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = i.read(buf)
                    if (n < 0) break
                    total += n
                    if (total > MAX_IMPORT_BYTES) { o.close(); out.delete(); throw IOException("$name is larger than ${MAX_IMPORT_BYTES shr 20} MiB") }
                    o.write(buf, 0, n)
                }
            }
        }
        val magic = out.inputStream().use { s -> ByteArray(4).also { s.read(it) } }
        if (!(magic[0] == 'P'.code.toByte() && magic[1] == 'K'.code.toByte())) {
            out.delete()
            throw IOException("$name is not a jar or zip file")
        }
        return out
    }
}

/** Gets finished mods to where Horizon Android can import them. */
object Exports {
    fun copyTo(context: Context, file: File, uri: Uri) {
        context.contentResolver.openOutputStream(uri, "wt")?.use { o -> file.inputStream().use { it.copyTo(o) } }
            ?: throw IOException("cannot write to the chosen file")
    }

    /**
     * Writes [file] into the folder the user granted once (normally "Horizon Android › Mods" from
     * Horizon Android's documents provider). An existing file of the same name is replaced only
     * because the user re-exports the same mod; anything else in the folder is untouched.
     */
    fun copyToTree(context: Context, file: File, treeUri: String): String {
        val tree = DocumentFile.fromTreeUri(context, Uri.parse(treeUri)) ?: throw IOException("the saved folder is no longer available")
        if (!tree.canWrite()) throw IOException("RustMod Forge may no longer write to ${tree.name}; pick the folder again")
        tree.findFile(file.name)?.delete()
        val target = tree.createFile("application/octet-stream", file.name) ?: throw IOException("could not create ${file.name}")
        copyTo(context, file, target.uri)
        return tree.name ?: "the chosen folder"
    }

    fun share(context: Context, file: File) {
        val uri = FileProvider.getUriForFile(context, context.packageName + ".files", file)
        val send = Intent(Intent.ACTION_SEND).setType("application/octet-stream").putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Horizon Android's launch intent, release or dev build, if installed. */
    fun launcherIntent(context: Context, preferred: String): Intent? =
        listOf(preferred, "dev.horizon.android", "dev.horizon.android.dev").distinct()
            .firstNotNullOfOrNull { context.packageManager.getLaunchIntentForPackage(it) }

    fun openLauncher(context: Context, preferred: String): Boolean {
        val intent = launcherIntent(context, preferred) ?: return false
        return try { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true } catch (_: ActivityNotFoundException) { false }
    }
}
