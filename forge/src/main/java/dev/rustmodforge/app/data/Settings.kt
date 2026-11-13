package dev.rustmodforge.app.data

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dev.rustmodforge.core.ai.AiConfig
import dev.rustmodforge.core.compat.TargetId
import dev.rustmodforge.core.pipeline.Quality
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** OpenRouter's endpoint; the free models are chosen from its live catalog. */
const val OPENROUTER_BASE = "https://openrouter.ai/api/v1"

/**
 * Ready-made AI providers. OpenRouter is the one the agent drives, with a list of free models it
 * falls back through; Pollinations needs no key at all; the rest are free tiers needing a key.
 */
enum class AiPreset(val label: String, val kind: AiConfig.Kind, val baseUrl: String, val model: String, val needsKey: Boolean, val hint: String) {
    OPENROUTER("OpenRouter (free models)", AiConfig.Kind.OPENAI_COMPATIBLE, OPENROUTER_BASE, "recursive/flint-v1.0:free", true,
        "Your own free OpenRouter key from openrouter.ai/keys. The app checks which of the free models exist right now and falls back between them; it never uses a paid model."),
    FREE("Free, no key", AiConfig.Kind.OPENAI_COMPATIBLE, "https://text.pollinations.ai/openai", "openai", false,
        "Pollinations' shared free endpoint. No account and no key; it is a shared queue, so a busy moment can be slow."),
    GEMINI("Gemini (free key)", AiConfig.Kind.OPENAI_COMPATIBLE, "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-flash-latest", true,
        "Free key from aistudio.google.com."),
    GROQ("Groq (free key)", AiConfig.Kind.OPENAI_COMPATIBLE, "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile", true,
        "Free key from console.groq.com."),
    ANTHROPIC("Anthropic (paid key)", AiConfig.Kind.ANTHROPIC, "https://api.anthropic.com", "claude-sonnet-4-5", true,
        "Your own Anthropic key."),
}

data class ForgeSettings(
    val aiEnabled: Boolean = false,
    val aiKind: AiConfig.Kind = AiConfig.Kind.OPENAI_COMPATIBLE,
    val aiBaseUrl: String = AiPreset.OPENROUTER.baseUrl,
    val aiModel: String = AiPreset.OPENROUTER.model,
    /** The agent's model preference order, best first; only free ones are used. */
    val aiModelPreference: List<String> = dev.rustmodforge.core.ai.OpenRouterProvider.DEFAULT_PREFERRED,
    /** Paid models stay off unless the user turns this on themselves. */
    val aiAllowPaid: Boolean = false,
    val agentMaxSteps: Int = 24,
    val agentTokenBudget: Int = 120_000,
    val aiKey: String = "",
    val aiTokenBudget: Int = 200_000,
    val buildServerUrl: String = "",
    val buildServerToken: String = "",
    val maxRepairs: Int = 3,
    val defaultQuality: Quality = Quality.ADVANCED,
    val targetAndroid: Boolean = true,
    val targetDesktop: Boolean = false,
    /** A folder the user picked once (normally Horizon Android › Mods), as a persisted tree URI. */
    val horizonModsTree: String = "",
    /** The launcher's resource pack folder, picked once, for one-tap pack export. */
    val horizonPacksTree: String = "",
    val launcherPackage: String = "dev.horizon.android",
    val debugLogging: Boolean = false,
) {
    val targets: List<TargetId> get() = buildList {
        if (targetAndroid) add(TargetId.HORIZON_ANDROID)
        if (targetDesktop) add(TargetId.HORIZON_DESKTOP)
    }.ifEmpty { listOf(TargetId.HORIZON_ANDROID) }

    val usesOpenRouter: Boolean get() = aiBaseUrl.trimEnd('/') == OPENROUTER_BASE

    fun aiConfig(): AiConfig? = if (!aiEnabled || aiModel.isBlank() || aiBaseUrl.isBlank()) null
    else AiConfig(aiKind, aiBaseUrl, aiModel, aiKey, tokenBudget = aiTokenBudget)

    /** The agent's provider: OpenRouter with fallback, or the configured OpenAI-compatible one. */
    fun agentProvider(historyFile: java.io.File?): dev.rustmodforge.core.ai.AiProvider? {
        if (!aiEnabled) return null
        return if (usesOpenRouter) {
            if (aiKey.isBlank()) null
            else dev.rustmodforge.core.ai.OpenRouterProvider(aiKey, aiModelPreference, aiAllowPaid, aiBaseUrl, historyFile)
        } else aiConfig()?.let { dev.rustmodforge.core.ai.AiAssistant.providerFor(it) }
    }
}

/**
 * Settings. Secrets (the AI key and the build server token) live in EncryptedSharedPreferences
 * backed by the Android keystore; if that is unavailable they are kept for this session only
 * and [secretsPersistent] says so.
 */
class SettingsStore(context: Context) {
    private val plain = context.getSharedPreferences("forge_settings", Context.MODE_PRIVATE)
    private val secure: SharedPreferences? = runCatching {
        EncryptedSharedPreferences.create(
            context, "forge_secrets",
            MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }.getOrNull()

    val secretsPersistent get() = secure != null

    private val _state = MutableStateFlow(read())
    val state: StateFlow<ForgeSettings> = _state.asStateFlow()

    private fun read(): ForgeSettings {
        val d = ForgeSettings()
        return ForgeSettings(
            aiEnabled = plain.getBoolean("ai_enabled", d.aiEnabled),
            aiKind = runCatching { AiConfig.Kind.valueOf(plain.getString("ai_kind", d.aiKind.name)!!) }.getOrDefault(d.aiKind),
            aiBaseUrl = plain.getString("ai_base", d.aiBaseUrl)!!,
            aiModel = plain.getString("ai_model", d.aiModel)!!,
            aiKey = secure?.getString("ai_key", "") ?: "",
            aiTokenBudget = plain.getInt("ai_budget", d.aiTokenBudget),
            buildServerUrl = plain.getString("build_url", d.buildServerUrl)!!,
            buildServerToken = secure?.getString("build_token", "") ?: "",
            maxRepairs = plain.getInt("max_repairs", d.maxRepairs),
            defaultQuality = runCatching { Quality.valueOf(plain.getString("quality", d.defaultQuality.name)!!) }.getOrDefault(d.defaultQuality),
            targetAndroid = plain.getBoolean("target_android", d.targetAndroid),
            targetDesktop = plain.getBoolean("target_desktop", d.targetDesktop),
            horizonModsTree = plain.getString("mods_tree", "")!!,
            horizonPacksTree = plain.getString("packs_tree", "")!!,
            aiModelPreference = plain.getString("ai_models", null)?.split('\n')?.filter { it.isNotBlank() }
                ?: dev.rustmodforge.core.ai.OpenRouterProvider.DEFAULT_PREFERRED,
            aiAllowPaid = plain.getBoolean("ai_paid", false),
            agentMaxSteps = plain.getInt("agent_steps", 24),
            agentTokenBudget = plain.getInt("agent_tokens", 120_000),
            launcherPackage = plain.getString("launcher", d.launcherPackage)!!,
            debugLogging = plain.getBoolean("debug", d.debugLogging),
        )
    }

    fun update(f: (ForgeSettings) -> ForgeSettings) {
        val s = f(_state.value)
        _state.value = s
        plain.edit()
            .putBoolean("ai_enabled", s.aiEnabled).putString("ai_kind", s.aiKind.name).putString("ai_base", s.aiBaseUrl.trim())
            .putString("ai_model", s.aiModel.trim()).putInt("ai_budget", s.aiTokenBudget).putString("build_url", s.buildServerUrl.trim())
            .putInt("max_repairs", s.maxRepairs).putString("quality", s.defaultQuality.name).putBoolean("target_android", s.targetAndroid)
            .putBoolean("target_desktop", s.targetDesktop).putString("mods_tree", s.horizonModsTree).putString("launcher", s.launcherPackage.trim())
            .putBoolean("debug", s.debugLogging)
            .apply()
        secure?.edit()?.putString("ai_key", s.aiKey.trim())?.putString("build_token", s.buildServerToken.trim())?.apply()
    }
}
