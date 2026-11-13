package dev.rustmodforge.core.build

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.TimeUnit

/** One compiler diagnostic, as `cargo --message-format=short` prints it. */
@Serializable
data class Diagnostic(val level: String, val file: String, val line: Int, val message: String)

@Serializable
data class BuildResult(val ran: Boolean, val success: Boolean, val log: String, val diagnostics: List<Diagnostic> = emptyList(), val backend: String = "")

/**
 * Compiles a generated native mod. A phone cannot run Horizon's desktop toolchain (the game is
 * rebuilt from source with the mod), so on Android only [RemoteBuildBackend] can compile; when
 * no backend is configured the step is reported as not run, never as passed.
 */
interface BuildBackend {
    val name: String
    fun available(): Boolean
    fun check(nativeTree: File, modId: String): BuildResult
}

object Diagnostics {
    private val re = Regex("""^(?:(.+?):(\d+):\d+: )?(error|warning)(?:\[\w+\])?: (.+)$""")
    fun parse(log: String): List<Diagnostic> = log.lines().mapNotNull { l ->
        re.find(l.trim())?.let { m -> Diagnostic(m.groupValues[3], m.groupValues[1], m.groupValues[2].toIntOrNull() ?: 0, m.groupValues[4]) }
    }
}

/**
 * `cargo check` of the mod's `[api]` crate as a member of a local Horizon checkout at the pinned
 * revision, the way the launcher stages trait mods (`native-crates/<mod>/`). Desktop and CI only.
 */
class LocalCargoBackend(private val horizonSource: File, private val cargo: String = "cargo", private val timeoutMinutes: Long = 60) : BuildBackend {
    override val name = "local cargo (${horizonSource.path})"

    override fun available(): Boolean = File(horizonSource, "crates/horizon-client/Cargo.toml").exists() &&
        runCatching { ProcessBuilder(cargo, "--version").redirectErrorStream(true).start().waitFor(30, TimeUnit.SECONDS) }.getOrDefault(false)

    override fun check(nativeTree: File, modId: String): BuildResult {
        val api = File(nativeTree, "mixins/$modId/api")
        if (!File(api, "Cargo.toml").exists()) return BuildResult(false, false, "no [api] crate at ${api.path}", backend = name)
        val staged = File(horizonSource, "native-crates/rmf-$modId")
        staged.deleteRecursively()
        api.copyRecursively(staged, overwrite = true)
        // Point horizon-client at the checkout instead of git, as the launcher does.
        val manifest = File(staged, "Cargo.toml")
        manifest.writeText(manifest.readText().replace(Regex("""horizon-client = \{[^}]*}"""), """horizon-client = { path = "../../crates/horizon-client" }"""))
        val root = File(horizonSource, "Cargo.toml")
        val original = root.readText()
        val lock = File(horizonSource, "Cargo.lock")
        val originalLock = lock.takeIf { it.exists() }?.readBytes()
        val member = "\"native-crates/rmf-$modId\""
        if (!original.contains(member)) root.writeText(original.replaceFirst("members = [", "members = [\n    $member,"))
        try {
            val pkg = Regex("""name = "([^"]+)"""").find(manifest.readText())!!.groupValues[1]
            val proc = ProcessBuilder(cargo, "check", "-p", pkg, "--message-format=short").directory(horizonSource).redirectErrorStream(true).start()
            val log = proc.inputStream.bufferedReader().readText()
            val done = proc.waitFor(timeoutMinutes, TimeUnit.MINUTES)
            val ok = done && proc.exitValue() == 0
            return BuildResult(true, ok, log.takeLast(20_000), Diagnostics.parse(log).map { it.copy(file = it.file.replace("native-crates/rmf-$modId/", "api/")) }, name)
        } finally {
            root.writeText(original)
            originalLock?.let { lock.writeBytes(it) }
            staged.deleteRecursively()
        }
    }
}

/**
 * Sends the `.hnmod` to a build server the user runs (tools/forge-build-server.py in this
 * repository): it answers `{"ran":true,"success":...,"log":"..."}`. The token, if any, is the
 * user's own; nothing is sent unless the user configured the URL.
 */
class RemoteBuildBackend(private val url: String, private val token: String?) : BuildBackend {
    override val name = "remote ($url)"
    override fun available() = url.startsWith("https://") || url.startsWith("http://127.0.0.1") || url.startsWith("http://localhost") || url.startsWith("http://10.")

    override fun check(nativeTree: File, modId: String): BuildResult {
        val zip = File.createTempFile("rmf-$modId", ".hnmod")
        try {
            Packager.pack(nativeTree, zip)
            val conn = URL(url.trimEnd('/') + "/check").openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.doOutput = true
            conn.connectTimeout = 20_000
            conn.readTimeout = 60 * 60_000
            conn.setRequestProperty("Content-Type", "application/zip")
            conn.setRequestProperty("X-Mod-Id", modId)
            token?.takeIf { it.isNotBlank() }?.let { conn.setRequestProperty("Authorization", "Bearer $it") }
            conn.outputStream.use { o -> zip.inputStream().use { it.copyTo(o) } }
            val body = (if (conn.responseCode in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.readText() ?: ""
            if (conn.responseCode !in 200..299) return BuildResult(false, false, "build server answered ${conn.responseCode}: ${body.take(500)}", backend = name)
            val r = Json { ignoreUnknownKeys = true }.decodeFromString(BuildResult.serializer(), body)
            return r.copy(diagnostics = r.diagnostics.ifEmpty { Diagnostics.parse(r.log) }, backend = name)
        } catch (e: Exception) {
            return BuildResult(false, false, "build server unreachable: ${e.message}", backend = name)
        } finally {
            zip.delete()
        }
    }
}

/** Horizon's own checker (`cargo horizon-mod check`), when its binary is installed. */
class HorizonModChecker(private val binary: File) {
    fun available() = binary.canExecute()
    fun check(file: File): BuildResult {
        val proc = ProcessBuilder(binary.path, "horizon-mod", "check", file.path).redirectErrorStream(true).start()
        val log = proc.inputStream.bufferedReader().readText()
        val done = proc.waitFor(5, TimeUnit.MINUTES)
        return BuildResult(true, done && proc.exitValue() == 0, log, backend = "cargo horizon-mod check")
    }
}
