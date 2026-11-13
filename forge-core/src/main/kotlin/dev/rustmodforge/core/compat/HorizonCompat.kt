package dev.rustmodforge.core.compat

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * What each Horizon target can actually load, from the sources read in
 * docs/rustmod-forge/research.md. Every generator asks this database before emitting a file,
 * so nothing is produced for a capability a target lacks.
 */
@Serializable
enum class TargetId { HORIZON_ANDROID, HORIZON_DESKTOP }

@Serializable
enum class Support { SUPPORTED, PARTIAL, UNSUPPORTED }

@Serializable
data class Capability(val key: String, val support: Support, val note: String)

@Serializable
data class TargetProfile(
    val id: TargetId,
    val name: String,
    val repository: String,
    val revision: String,
    val minecraft: String,
    val launcherPackage: String?,
    val contentApis: List<String>,
    val loadsHmod: Boolean,
    val loadsHnmod: Boolean,
    val capabilities: List<Capability>,
    val importGuide: List<String>,
    /** Living mob templates content mods may declare entity types from (empty: projectiles only). */
    val livingTemplates: List<String> = emptyList(),
    /** Entity type JSON fields the target's reader accepts. */
    val entityTypeFields: List<String> = listOf("template", "item", "damage"),
    val fluids: Boolean = false,
) {
    fun capability(key: String) = capabilities.firstOrNull { it.key == key }
}

@Serializable
data class HookEntry(val name: String, val version: Int, val side: String = "", val contract: String = "")

@Serializable
data class HookCatalog(val source: Map<String, String>? = null, val hooks: List<HookEntry>, val helpers: List<String>)

object HorizonCompat {
    const val MINECRAFT = "26.3"
    const val UPSTREAM_REVISION = "6c4c0347f9926e3b1d5994e7fb8b1ba5e68ddf70"
    const val ANDROID_REVISION = "150a414b09a18c900489d9462a7fc035dae744b7"
    /** horizon-mixins commit the upstream launcher pins (`launcher/src/native_mods.rs`, `MIXINS_REV`). */
    const val MIXINS_REVISION = "5a64af938ec86b00d53d16a408aabc0038fb3e57"
    const val NATIVE_HOOKS_API = 415
    const val ANDROID_PACKAGE = "dev.horizon.android"
    const val ANDROID_DOCUMENTS_AUTHORITY = "dev.horizon.android.documents"

    /**
     * Default attributes of the living templates, from vanilla 26.3's attribute suppliers
     * (`LivingEntity`, `Mob`, `Monster`, `Zombie`). Horizon refuses an override of an attribute
     * the template does not have, so only these are emitted. Kept to the ones every supplier
     * chain certainly includes.
     */
    val templateAttributes: Map<String, Set<String>> = mapOf(
        "minecraft:zombie" to setOf("minecraft:max_health", "minecraft:follow_range", "minecraft:knockback_resistance",
            "minecraft:movement_speed", "minecraft:attack_damage", "minecraft:armor", "minecraft:armor_toughness",
            "minecraft:spawn_reinforcements", "minecraft:step_height", "minecraft:scale"),
        "minecraft:wandering_trader" to setOf("minecraft:max_health", "minecraft:follow_range", "minecraft:knockback_resistance",
            "minecraft:movement_speed", "minecraft:armor", "minecraft:armor_toughness", "minecraft:step_height", "minecraft:scale"),
        "minecraft:villager" to setOf("minecraft:max_health", "minecraft:follow_range", "minecraft:knockback_resistance",
            "minecraft:movement_speed", "minecraft:armor", "minecraft:armor_toughness", "minecraft:step_height", "minecraft:scale"),
    )

    val hookCatalog: HookCatalog by lazy {
        val text = HorizonCompat::class.java.getResourceAsStream("/rustmodforge/horizon-hooks.json")?.bufferedReader()?.readText()
            ?: error("horizon-hooks.json missing from the engine's resources")
        Json { ignoreUnknownKeys = true }.decodeFromString(HookCatalog.serializer(), text.replace(Regex("\"nativeHooksApi\": (\\d+)"), "\"nativeHooksApi\": \"$1\""))
    }

    fun hasHook(name: String) = hookCatalog.hooks.any { it.name == name }
    fun hasHelper(name: String) = name in hookCatalog.helpers

    val android = TargetProfile(
        id = TargetId.HORIZON_ANDROID,
        name = "Horizon Android (RxLauncher Rust Edition)",
        repository = "github.com/RxLauncherTeam/RxLauncher-Rust-Edition",
        revision = ANDROID_REVISION, minecraft = MINECRAFT, launcherPackage = ANDROID_PACKAGE,
        contentApis = listOf("0.1", "0.2", "0.3"), loadsHmod = true, loadsHnmod = false,
        capabilities = listOf(
            Capability("content.assets", Support.SUPPORTED, "Textures, models, item model definitions, sounds, languages load from a .hmod"),
            Capability("content.data", Support.SUPPORTED, "Recipes, loot, tags, advancements, worldgen, biome modifiers load from a .hmod"),
            Capability("content.functions", Support.PARTIAL, "Data pack functions and #minecraft:tick run (functions.rs); content-mod functions not yet tried on a device"),
            Capability("content.blocks_items", Support.PARTIAL, "Declared from vanilla templates: template behaviour, own textures and numbers"),
            Capability("entity.type", Support.PARTIAL, "Content mods declare only snowball-like projectile types at this revision (horizon-mods ENTITY_TEMPLATES); a creature's body is a tagged vanilla mob managed by functions"),
            Capability("entity.model", Support.PARTIAL, "No custom entity model API: reconstructed as a display-entity rig (item models per bone) driven by functions"),
            Capability("entity.animation", Support.PARTIAL, "Rig bones posed by functions each frame step with display interpolation"),
            Capability("entity.ai", Support.PARTIAL, "Template goals plus function-driven behaviours (watch, stalk, vanish, freeze, effects)"),
            Capability("entity.sounds", Support.SUPPORTED, "playsound with the mod's sound events"),
            Capability("entity.particles", Support.PARTIAL, "Vanilla particles only; custom particle types need code"),
            Capability("client.camera_shake", Support.PARTIAL, "Only from a WASM client mod (render.shake, experimental capability)"),
            Capability("client.overlay", Support.PARTIAL, "Approximated with title/font images; no custom screen rendering"),
            Capability("native.code", Support.UNSUPPORTED, "Source-only .hnmod native mods are not supported on Android (README, android-content.md)"),
            Capability("wasm.code", Support.PARTIAL, "Sandboxed mod.wasm on 64-bit APKs: player/HUD/chat/commands, no entity API"),
            Capability("java.code", Support.UNSUPPORTED, "Java/Fabric/Forge code never runs in Horizon"),
        ),
        importGuide = listOf(
            "Open Horizon Android and go to Mods.",
            "Press Import file and pick the exported .hmod (or export straight into the 'Horizon Android › Mods' folder from RustMod Forge).",
            "Open Installed, expand Mods and switch the mod on. It applies at the next game start.",
            "In a world: entity behaviours run as data pack functions; use a new world or /reload after turning the mod on.",
            "Creatures spawn through the mod's functions; to place one yourself use /function <mod id>:summon/<creature> (needs cheats).",
        ),
    )

    val desktop = TargetProfile(
        id = TargetId.HORIZON_DESKTOP,
        name = "Horizon (upstream desktop launcher)",
        repository = "github.com/horizon-rust/horizon",
        revision = UPSTREAM_REVISION, minecraft = MINECRAFT, launcherPackage = null,
        contentApis = listOf("0.2"), loadsHmod = true, loadsHnmod = true,
        capabilities = listOf(
            Capability("content.assets", Support.SUPPORTED, "As Android"),
            Capability("content.data", Support.SUPPORTED, "As Android"),
            Capability("content.functions", Support.PARTIAL, "Data pack functions run"),
            Capability("content.blocks_items", Support.PARTIAL, "Templates"),
            Capability("entity.type", Support.SUPPORTED, "Living template + register_goals replaces the AI"),
            Capability("entity.model", Support.SUPPORTED, "layer_definitions + mob_submit draw the mod's own model"),
            Capability("entity.animation", Support.PARTIAL, "Keyframes compiled into Rust, applied in mob_submit"),
            Capability("entity.ai", Support.SUPPORTED, "Rust Goal impls through register_goals"),
            Capability("native.code", Support.SUPPORTED, "The launcher compiles .hnmod source into the game (desktop toolchain required)"),
            Capability("java.code", Support.UNSUPPORTED, "Java code never runs in Horizon"),
        ),
        importGuide = listOf(
            "Copy the .hmod into the game folder's horizon-mods/ and the .hnmod into horizon-native-mods/.",
            "Run: horizon-launcher native-build --trust-native-code (needs a Rust toolchain; review the source first).",
            "Turn both on in Options > Mods.",
        ),
        livingTemplates = listOf("minecraft:zombie", "minecraft:villager", "minecraft:wandering_trader"),
        entityTypeFields = listOf("template", "item", "damage", "attributes"),
        fluids = true,
    )

    fun profile(id: TargetId) = if (id == TargetId.HORIZON_ANDROID) android else desktop
}
