package dev.rustmodforge.core.model

import kotlinx.serialization.Serializable

/**
 * The internal representation of an analysed Java mod. Every stage after analysis reads only
 * this (never the jar again), so a project can be resumed from its saved analysis.
 */

@Serializable
enum class Loader { FABRIC, QUILT, FORGE, NEOFORGE, LEGACY_FORGE, DATA_OR_RESOURCE_PACK, UNKNOWN }

@Serializable
enum class DependencyKind { REQUIRED, OPTIONAL, INCOMPATIBLE, EMBEDDED }

@Serializable
data class DependencySpec(
    val id: String,
    val versionRange: String = "*",
    val kind: DependencyKind,
    val side: String = "both",
    /** Which file declared it (`fabric.mod.json`, `META-INF/mods.toml`, ...). */
    val declaredIn: String,
)

@Serializable
data class ModMetadata(
    val modId: String,
    val name: String,
    val version: String,
    val description: String = "",
    val authors: List<String> = emptyList(),
    val license: String = "",
    val loader: Loader,
    /** As declared (`>=1.20.1`, `[1.20.1,1.21)`), or inferred from pack format. */
    val minecraftVersion: String = "",
    val loaderVersion: String = "",
    val dependencies: List<DependencySpec> = emptyList(),
    val entrypoints: List<String> = emptyList(),
    val mixinConfigs: List<String> = emptyList(),
    val accessWideners: List<String> = emptyList(),
    val embeddedJars: List<String> = emptyList(),
    /** Every mod id the metadata files declared (a jar can carry several). */
    val declaredModIds: List<String> = emptyList(),
    /** The jar path of the mod's logo/icon, for the packs' `pack.png`. */
    val iconPath: String = "",
)

@Serializable
enum class ResourceKind {
    TEXTURE, TEXTURE_META, BLOCK_MODEL, ITEM_MODEL_DEFINITION, BLOCKSTATE, GEO_MODEL, GECKO_ANIMATION,
    BEDROCK_ANIMATION_CONTROLLER, SOUND_DEFINITIONS, SOUND, LANG, PARTICLE_DEFINITION, SHADER, FONT, ATLAS,
    RECIPE, LOOT_TABLE, ADVANCEMENT, TAG, WORLDGEN, STRUCTURE_NBT, BIOME_MODIFIER, FUNCTION, DAMAGE_TYPE,
    PREDICATE, ITEM_MODIFIER, OTHER_DATA, OTHER_ASSET, CLASS, MIXIN_CONFIG, ACCESS_WIDENER, METADATA,
    NESTED_JAR, OTHER,
}

@Serializable
data class ResourceRef(val path: String, val kind: ResourceKind, val namespace: String = "", val size: Long = 0)

@Serializable
enum class RegistryKind {
    ENTITY_TYPE, ITEM, BLOCK, BLOCK_ENTITY, SOUND_EVENT, PARTICLE_TYPE, MOB_EFFECT, CREATIVE_TAB, MENU,
    RECIPE_SERIALIZER, ENCHANTMENT, ATTRIBUTE, OTHER,
}

@Serializable
data class Registration(
    val kind: RegistryKind,
    /** `namespace:path`. */
    val id: String,
    /** The class whose static initializer (or init method) registers it. */
    val declaringClass: String,
    /** The registered object's class, when the bytecode names it (an entity's constructor). */
    val valueClass: String? = null,
    /** The static field the registry object is stored in, when known. */
    val field: String? = null,
    val details: Map<String, String> = emptyMap(),
    val evidence: String = "",
)

@Serializable
enum class GoalSelectorKind { GOAL, TARGET }

/** One `goalSelector.addGoal(priority, new XGoal(args))` call. */
@Serializable
data class GoalInfo(
    val selector: GoalSelectorKind,
    val priority: Int,
    /** Canonical vanilla goal name (`MeleeAttackGoal`) or the mod's class for custom goals. */
    val goal: String,
    val custom: Boolean,
    /** Literal constructor arguments in order: numbers, booleans, class literals. */
    val args: List<String> = emptyList(),
    /** Class literals among the arguments (`Player`), canonical names. */
    val targets: List<String> = emptyList(),
)

/**
 * A behaviour recognised from bytecode. Traits are what reconstruction maps onto Horizon:
 * they describe what the original code does, with the evidence that shows it.
 */
@Serializable
enum class TraitKind {
    STALK_PLAYER, WATCH_FROM_DISTANCE, VANISH_WHEN_APPROACHED, VANISH_WHEN_LOOKED_AT, FREEZE_WHEN_LOOKED_AT,
    TELEPORT_NEAR_PLAYER, LINE_OF_SIGHT_CHECK, NIGHT_ONLY, DAY_ONLY, APPLY_EFFECT_TO_PLAYER, PLAY_SOUND,
    SPAWN_PARTICLES, JUMPSCARE_OVERLAY, BREAK_BLOCKS, CUSTOM_MELEE, TOGGLE_INVISIBILITY, FOG_OR_DARKNESS,
    PERSISTENT, DESPAWN_WHEN_FAR, CUSTOM_SPAWN_RULE, CHASE_PLAYER, FLEE_LIGHT, CUSTOM_RENDERER, CUSTOM_PACKET,
}

@Serializable
data class BehaviourTrait(
    val kind: TraitKind,
    val params: Map<String, String> = emptyMap(),
    /** `Class.method: what was seen`. */
    val evidence: List<String> = emptyList(),
)

@Serializable
data class EntitySounds(
    val ambient: String? = null,
    val hurt: String? = null,
    val death: String? = null,
    val step: String? = null,
    val other: List<String> = emptyList(),
)

@Serializable
data class SpawnInfo(
    val category: String = "",
    val biomes: List<String> = emptyList(),
    val weight: Int? = null,
    val minCount: Int? = null,
    val maxCount: Int? = null,
    val source: String = "",
)

@Serializable
data class EntityInfo(
    val id: String,
    val className: String,
    /** The nearest vanilla superclass, canonical (`Monster`, `PathfinderMob`, `Animal`...). */
    val vanillaBase: String,
    val superChain: List<String> = emptyList(),
    val category: String = "",
    val width: Double? = null,
    val height: Double? = null,
    val attributes: Map<String, Double> = emptyMap(),
    val goals: List<GoalInfo> = emptyList(),
    val traits: List<BehaviourTrait> = emptyList(),
    val sounds: EntitySounds = EntitySounds(),
    val usesGeckoLib: Boolean = false,
    val geoModel: String? = null,
    val texture: String? = null,
    val animationFile: String? = null,
    val javaModelLayer: String? = null,
    val rendererClass: String? = null,
    val spawn: SpawnInfo? = null,
    val unresolved: List<String> = emptyList(),
)

@Serializable
data class ItemInfo(
    val id: String,
    val className: String? = null,
    val vanillaBase: String = "Item",
    val properties: Map<String, String> = emptyMap(),
)

@Serializable
data class BlockInfo(
    val id: String,
    val className: String? = null,
    val vanillaBase: String = "Block",
    val properties: Map<String, String> = emptyMap(),
    val hasBlockEntity: Boolean = false,
)

@Serializable
data class SoundEventInfo(val id: String, val files: List<String>, val subtitle: String? = null)

@Serializable
data class MixinInfo(val config: String, val mixinClass: String, val targets: List<String>, val injections: List<String>)

@Serializable
data class ApiUsage(val api: String, val classes: List<String>, val why: String)

@Serializable
data class DependencyEdge(val from: String, val to: String, val relation: String)

@Serializable
data class DependencyGraph(val nodes: List<String> = emptyList(), val edges: List<DependencyEdge> = emptyList())

@Serializable
data class ClassSummary(
    val name: String,
    val superName: String?,
    val interfaces: List<String>,
    val methodCount: Int,
    val fieldCount: Int,
    val size: Long,
    /** Canonical vanilla concept the class extends, when it extends one (`Monster`, `Goal`, `Item`...). */
    val vanillaBase: String? = null,
)

@Serializable
data class ModAnalysis(
    val sourceFile: String,
    val sha256: String,
    val metadata: ModMetadata,
    val resources: List<ResourceRef>,
    val classes: List<ClassSummary>,
    val registrations: List<Registration>,
    val entities: List<EntityInfo>,
    val items: List<ItemInfo>,
    val blocks: List<BlockInfo>,
    val sounds: List<SoundEventInfo>,
    val geoModels: List<String>,
    val animations: List<String>,
    val mixins: List<MixinInfo>,
    val unsupportedApis: List<ApiUsage>,
    val graph: DependencyGraph,
    val nested: List<ModAnalysis> = emptyList(),
    val warnings: List<String> = emptyList(),
) {
    val namespaces: Set<String> get() = resources.mapNotNull { it.namespace.takeIf { n -> n.isNotEmpty() } }.toSet()
    fun resourcesOf(kind: ResourceKind) = resources.filter { it.kind == kind }
}
