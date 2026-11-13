package dev.rustmodforge.core.bytecode

/**
 * Vanilla Minecraft names as compiled mods reference them. A mod jar names game classes and
 * members in the mapping its loader runs on: Mojang's official names (NeoForge, Forge's class
 * names), SRG member ids (Forge 1.17–1.20.4: `m_8099_`), or Fabric intermediary
 * (`class_1588`, `method_5959`). Concepts are matched against every known spelling.
 *
 * Mojang names are authoritative. SRG and intermediary ids are best-effort: an id missing
 * here only means that call is not recognised (it is then listed as unresolved), never that a
 * behaviour is invented.
 */
object Vanilla {
    private fun mc(path: String) = "net/minecraft/$path"

    /** Class concept → internal names. */
    val classes: Map<String, Set<String>> = mapOf(
        "Entity" to setOf(mc("world/entity/Entity"), mc("class_1297"), mc("entity/Entity")),
        "LivingEntity" to setOf(mc("world/entity/LivingEntity"), mc("class_1309"), mc("entity/LivingEntity")),
        "Mob" to setOf(mc("world/entity/Mob"), mc("class_1308"), mc("entity/mob/MobEntity")),
        "PathfinderMob" to setOf(mc("world/entity/PathfinderMob"), mc("class_1314"), mc("entity/mob/PathAwareEntity")),
        "Monster" to setOf(mc("world/entity/monster/Monster"), mc("class_1588"), mc("entity/mob/HostileEntity")),
        "AgeableMob" to setOf(mc("world/entity/AgeableMob"), mc("class_1296"), mc("entity/passive/PassiveEntity")),
        "Animal" to setOf(mc("world/entity/animal/Animal"), mc("class_1429"), mc("entity/passive/AnimalEntity")),
        "TamableAnimal" to setOf(mc("world/entity/TamableAnimal"), mc("class_1321"), mc("entity/passive/TameableEntity")),
        "FlyingMob" to setOf(mc("world/entity/FlyingMob"), mc("class_1307"), mc("entity/mob/FlyingEntity")),
        "WaterAnimal" to setOf(mc("world/entity/animal/WaterAnimal"), mc("class_1480"), mc("entity/passive/WaterCreatureEntity")),
        "Zombie" to setOf(mc("world/entity/monster/Zombie"), mc("class_1642"), mc("entity/mob/ZombieEntity")),
        "AbstractSkeleton" to setOf(mc("world/entity/monster/AbstractSkeleton"), mc("class_1547"), mc("entity/mob/AbstractSkeletonEntity")),
        "Spider" to setOf(mc("world/entity/monster/Spider"), mc("class_1628"), mc("entity/mob/SpiderEntity")),
        "EnderMan" to setOf(mc("world/entity/monster/EnderMan"), mc("class_1560"), mc("entity/mob/EndermanEntity")),
        "Creeper" to setOf(mc("world/entity/monster/Creeper"), mc("class_1548"), mc("entity/mob/CreeperEntity")),
        "Projectile" to setOf(mc("world/entity/projectile/Projectile"), mc("class_1676"), mc("entity/projectile/ProjectileEntity")),
        "ThrowableItemProjectile" to setOf(mc("world/entity/projectile/ThrowableItemProjectile"), mc("class_3857"), mc("entity/projectile/thrown/ThrownItemEntity")),
        "Player" to setOf(mc("world/entity/player/Player"), mc("class_1657"), mc("entity/player/PlayerEntity")),
        "Goal" to setOf(mc("world/entity/ai/goal/Goal"), mc("class_1352"), mc("entity/ai/goal/Goal")),
        "TargetGoal" to setOf(mc("world/entity/ai/goal/target/TargetGoal"), mc("class_1405"), mc("entity/ai/goal/TrackTargetGoal")),
        "Item" to setOf(mc("world/item/Item"), mc("class_1792"), mc("item/Item")),
        "SwordItem" to setOf(mc("world/item/SwordItem"), mc("class_1829"), mc("item/SwordItem")),
        "BlockItem" to setOf(mc("world/item/BlockItem"), mc("class_1747"), mc("item/BlockItem")),
        "SpawnEggItem" to setOf(mc("world/item/SpawnEggItem"), mc("class_1826"), mc("item/SpawnEggItem")),
        "Block" to setOf(mc("world/level/block/Block"), mc("class_2248"), mc("block/Block")),
        "BaseEntityBlock" to setOf(mc("world/level/block/BaseEntityBlock"), mc("class_2237"), mc("block/BlockWithEntity")),
        "BlockEntity" to setOf(mc("world/level/block/entity/BlockEntity"), mc("class_2586"), mc("block/entity/BlockEntity")),
        "Screen" to setOf(mc("client/gui/screens/Screen"), mc("class_437"), mc("client/gui/screen/Screen")),
        "EntityRenderer" to setOf(mc("client/renderer/entity/EntityRenderer"), mc("class_897"), mc("client/render/entity/EntityRenderer")),
        "LivingEntityRenderer" to setOf(mc("client/renderer/entity/LivingEntityRenderer"), mc("class_922"), mc("client/render/entity/LivingEntityRenderer")),
        "MobRenderer" to setOf(mc("client/renderer/entity/MobRenderer"), mc("class_927"), mc("client/render/entity/MobEntityRenderer")),
        "EntityModel" to setOf(mc("client/model/EntityModel"), mc("class_583"), mc("client/render/entity/model/EntityModel")),
        "GeoEntity" to setOf("software/bernie/geckolib/animatable/GeoEntity", "software/bernie/geckolib/core/animatable/GeoAnimatable",
            "software/bernie/geckolib/animatable/GeoAnimatable", "software/bernie/geckolib3/core/IAnimatable"),
        "GeoEntityRenderer" to setOf("software/bernie/geckolib/renderer/GeoEntityRenderer", "software/bernie/geckolib3/renderers/geo/GeoEntityRenderer"),
        "GeoModel" to setOf("software/bernie/geckolib/model/GeoModel", "software/bernie/geckolib/model/DefaultedEntityGeoModel",
            "software/bernie/geckolib/model/DefaultedGeoModel", "software/bernie/geckolib3/model/AnimatedGeoModel",
            "software/bernie/geckolib3/model/AnimatedTickingGeoModel"),
    )

    /** Goal class concept → internal names (all in vanilla's ai/goal packages). */
    val goals: Map<String, Set<String>> = mapOf(
        "FloatGoal" to setOf(mc("world/entity/ai/goal/FloatGoal"), mc("class_1347"), mc("entity/ai/goal/SwimGoal")),
        "MeleeAttackGoal" to setOf(mc("world/entity/ai/goal/MeleeAttackGoal"), mc("class_1366"), mc("entity/ai/goal/MeleeAttackGoal")),
        "WaterAvoidingRandomStrollGoal" to setOf(mc("world/entity/ai/goal/WaterAvoidingRandomStrollGoal"), mc("class_1394"), mc("entity/ai/goal/WanderAroundFarGoal")),
        "RandomStrollGoal" to setOf(mc("world/entity/ai/goal/RandomStrollGoal"), mc("class_1379"), mc("entity/ai/goal/WanderAroundGoal")),
        "LookAtPlayerGoal" to setOf(mc("world/entity/ai/goal/LookAtPlayerGoal"), mc("class_1361"), mc("entity/ai/goal/LookAtEntityGoal")),
        "RandomLookAroundGoal" to setOf(mc("world/entity/ai/goal/RandomLookAroundGoal"), mc("class_1376"), mc("entity/ai/goal/LookAroundGoal")),
        "NearestAttackableTargetGoal" to setOf(mc("world/entity/ai/goal/target/NearestAttackableTargetGoal"), mc("class_1400"), mc("entity/ai/goal/ActiveTargetGoal")),
        "HurtByTargetGoal" to setOf(mc("world/entity/ai/goal/target/HurtByTargetGoal"), mc("class_1399"), mc("entity/ai/goal/RevengeGoal")),
        "AvoidEntityGoal" to setOf(mc("world/entity/ai/goal/AvoidEntityGoal"), mc("class_1338"), mc("entity/ai/goal/FleeEntityGoal")),
        "LeapAtTargetGoal" to setOf(mc("world/entity/ai/goal/LeapAtTargetGoal"), mc("class_1359"), mc("entity/ai/goal/PounceAtTargetGoal")),
        "PanicGoal" to setOf(mc("world/entity/ai/goal/PanicGoal"), mc("class_1374"), mc("entity/ai/goal/EscapeDangerGoal")),
        "MoveTowardsTargetGoal" to setOf(mc("world/entity/ai/goal/MoveTowardsTargetGoal"), mc("entity/ai/goal/WanderAroundPointOfInterestGoal")),
        "OpenDoorGoal" to setOf(mc("world/entity/ai/goal/OpenDoorGoal"), mc("entity/ai/goal/LongDoorInteractGoal")),
        "BreakDoorGoal" to setOf(mc("world/entity/ai/goal/BreakDoorGoal"), mc("entity/ai/goal/BreakDoorGoal")),
        "RestrictSunGoal" to setOf(mc("world/entity/ai/goal/RestrictSunGoal"), mc("entity/ai/goal/AvoidSunlightGoal")),
        "FleeSunGoal" to setOf(mc("world/entity/ai/goal/FleeSunGoal"), mc("entity/ai/goal/EscapeSunlightGoal")),
    )

    /** Method concept → names. */
    val methods: Map<String, Set<String>> = mapOf(
        "registerGoals" to setOf("registerGoals", "m_8099_", "method_5959", "initGoals"),
        "addGoal" to setOf("addGoal", "m_25352_", "method_6411", "add"),
        "attributeAdd" to setOf("add", "m_22268_", "m_22266_", "method_26868", "method_26867"),
        "distanceToSqr" to setOf("distanceToSqr", "m_20280_", "m_20275_", "method_5858", "method_5649", "squaredDistanceTo"),
        "distanceTo" to setOf("distanceTo", "m_20270_", "method_5739"),
        "hasLineOfSight" to setOf("hasLineOfSight", "m_142582_", "method_6057", "canSee"),
        "getNearestPlayer" to setOf("getNearestPlayer", "m_45930_", "m_45924_", "method_18460", "method_18459", "getClosestPlayer"),
        "isDay" to setOf("isDay", "m_46461_", "method_8530"),
        "isNight" to setOf("isNight", "m_46462_", "method_23886"),
        "getDayTime" to setOf("getDayTime", "m_46468_", "method_8532", "getTimeOfDay"),
        "discard" to setOf("discard", "m_146870_", "method_31472", "remove", "m_142687_", "method_5650", "kill", "m_6074_", "method_5768"),
        "playSound" to setOf("playSound", "m_5496_", "m_5594_", "m_6263_", "method_5783", "method_8396", "m_247517_", "playLocalSound", "m_7785_"),
        "addParticle" to setOf("addParticle", "m_7106_", "method_8406", "sendParticles", "m_8767_", "method_14199"),
        "addEffect" to setOf("addEffect", "m_7292_", "m_147207_", "method_6092", "addStatusEffect"),
        "teleportTo" to setOf("teleportTo", "m_6021_", "method_5859", "randomTeleport", "m_20984_", "method_6082", "requestTeleport", "moveTo", "m_7678_", "method_5808"),
        "setInvisible" to setOf("setInvisible", "m_6842_", "method_5648"),
        "setTarget" to setOf("setTarget", "m_6710_", "method_5980"),
        "getTarget" to setOf("getTarget", "m_5448_", "method_5968"),
        "navigationMoveTo" to setOf("moveTo", "m_26519_", "m_5624_", "method_6337", "method_6335", "startMovingTo"),
        "getNavigation" to setOf("getNavigation", "m_21573_", "method_5942"),
        "lookAt" to setOf("setLookAt", "m_24960_", "m_148051_", "method_6226", "lookAt", "m_21391_", "method_5951"),
        "lookVector" to setOf("getViewVector", "m_20252_", "method_5828", "getLookAngle", "m_20154_", "method_5720", "getRotationVec"),
        "vecDot" to setOf("dot", "m_82526_", "method_1026", "dotProduct"),
        "doHurtTarget" to setOf("doHurtTarget", "m_7327_", "method_6121", "tryAttack"),
        "hurt" to setOf("hurt", "m_6469_", "method_5643", "damage", "hurtServer"),
        "destroyBlock" to setOf("destroyBlock", "m_46961_", "method_22352", "breakBlock", "removeBlock", "m_7471_", "method_8650"),
        "removeWhenFarAway" to setOf("removeWhenFarAway", "m_6785_", "method_5974", "canImmediatelyDespawn"),
        "requiresCustomPersistence" to setOf("requiresCustomPersistence", "m_8023_", "method_17326", "cannotDespawn"),
        "isSunBurnTick" to setOf("isSunBurnTick", "m_21527_", "method_5972", "isAffectedByDaylight"),
        "getAmbientSound" to setOf("getAmbientSound", "m_7515_", "method_5994"),
        "getHurtSound" to setOf("getHurtSound", "m_7975_", "method_6011"),
        "getDeathSound" to setOf("getDeathSound", "m_5592_", "method_6002"),
        "playStepSound" to setOf("playStepSound", "m_7355_", "method_5712", "getStepSound"),
        "tick" to setOf("tick", "m_8119_", "method_5773", "aiStep", "m_8107_", "method_6007", "customServerAiStep", "m_8024_", "method_5958", "baseTick", "m_6075_", "method_5670"),
        "canUse" to setOf("canUse", "m_8036_", "method_6264"),
        "canContinueToUse" to setOf("canContinueToUse", "m_8045_", "method_6266"),
        "goalTick" to setOf("tick", "m_8037_", "method_6268"),
        "goalStart" to setOf("start", "m_8056_", "method_6269"),
        "goalStop" to setOf("stop", "m_8041_", "method_6270"),
        "blit" to setOf("blit", "m_280163_", "m_280218_", "m_280398_", "method_25290", "method_25302", "drawTexture"),
        "spawnPlacementRegister" to setOf("register", "m_21754_", "method_20637"),
        "createBodyLayer" to setOf("createBodyLayer", "getTexturedModelData"),
        "texOffs" to setOf("texOffs", "m_171514_", "method_32101", "uv"),
        "addBox" to setOf("addBox", "m_171481_", "m_171488_", "m_171496_", "m_171506_", "m_171517_", "m_171525_", "method_32097", "method_32098", "method_32096", "cuboid"),
        "partOffset" to setOf("offset", "m_171419_", "method_32090", "pivot"),
        "partOffsetAndRotation" to setOf("offsetAndRotation", "m_171423_", "method_32091", "of"),
        "addOrReplaceChild" to setOf("addOrReplaceChild", "m_171599_", "method_32117", "addChild"),
        "layerCreate" to setOf("create", "m_171565_", "method_32110", "of"),
    )

    /** `Attributes` static fields → Horizon (26.3) attribute ids. */
    val attributes: Map<String, String> = buildMap {
        fun alias(id: String, vararg names: String) { for (n in names) this[n] = id }
        alias("minecraft:max_health", "MAX_HEALTH", "GENERIC_MAX_HEALTH", "f_22276_", "field_23716")
        alias("minecraft:follow_range", "FOLLOW_RANGE", "GENERIC_FOLLOW_RANGE", "f_22277_", "field_23717")
        alias("minecraft:knockback_resistance", "KNOCKBACK_RESISTANCE", "GENERIC_KNOCKBACK_RESISTANCE", "f_22278_", "field_23718")
        alias("minecraft:movement_speed", "MOVEMENT_SPEED", "GENERIC_MOVEMENT_SPEED", "f_22279_", "field_23719")
        alias("minecraft:flying_speed", "FLYING_SPEED", "GENERIC_FLYING_SPEED", "f_22280_", "field_23720")
        alias("minecraft:attack_damage", "ATTACK_DAMAGE", "GENERIC_ATTACK_DAMAGE", "f_22281_", "field_23721")
        alias("minecraft:attack_knockback", "ATTACK_KNOCKBACK", "GENERIC_ATTACK_KNOCKBACK", "f_22282_", "field_23722")
        alias("minecraft:attack_speed", "ATTACK_SPEED", "GENERIC_ATTACK_SPEED", "f_22283_", "field_23723")
        alias("minecraft:armor", "ARMOR", "GENERIC_ARMOR", "f_22284_", "field_23724")
        alias("minecraft:armor_toughness", "ARMOR_TOUGHNESS", "GENERIC_ARMOR_TOUGHNESS", "f_22285_", "field_23725")
        alias("minecraft:spawn_reinforcements", "SPAWN_REINFORCEMENTS_CHANCE", "ZOMBIE_SPAWN_REINFORCEMENTS")
        alias("minecraft:step_height", "STEP_HEIGHT", "GENERIC_STEP_HEIGHT")
        alias("minecraft:scale", "SCALE", "GENERIC_SCALE")
    }

    /** Owners of the `Attributes` constants. */
    val attributeOwners = setOf(mc("world/entity/ai/attributes/Attributes"), mc("class_5134"), mc("entity/attribute/EntityAttributes"))

    /** `MobEffects` constants → effect ids. */
    val effects: Map<String, String> = buildMap {
        fun alias(id: String, vararg names: String) { for (n in names) this[n] = id }
        alias("minecraft:blindness", "BLINDNESS")
        alias("minecraft:darkness", "DARKNESS")
        alias("minecraft:slowness", "MOVEMENT_SLOWDOWN", "SLOWNESS")
        alias("minecraft:nausea", "CONFUSION", "NAUSEA")
        alias("minecraft:weakness", "WEAKNESS")
        alias("minecraft:wither", "WITHER")
        alias("minecraft:poison", "POISON")
        alias("minecraft:levitation", "LEVITATION")
        alias("minecraft:glowing", "GLOWING")
        alias("minecraft:invisibility", "INVISIBILITY")
        alias("minecraft:night_vision", "NIGHT_VISION")
        alias("minecraft:hunger", "HUNGER")
        alias("minecraft:mining_fatigue", "DIG_SLOWDOWN", "MINING_FATIGUE")
    }

    /** `MobCategory` constants. */
    val mobCategories = mapOf(
        "MONSTER" to "monster", "CREATURE" to "creature", "AMBIENT" to "ambient", "WATER_CREATURE" to "water_creature",
        "AXOLOTLS" to "axolotls", "UNDERGROUND_WATER_CREATURE" to "underground_water_creature", "WATER_AMBIENT" to "water_ambient",
        "MISC" to "misc", "field_6302" to "monster", "field_6294" to "creature", "field_6303" to "ambient", "field_6300" to "water_creature",
        "field_17715" to "misc",
    )

    private val classIndex: Map<String, String> = buildMap { classes.forEach { (k, v) -> v.forEach { put(it, k) } } }
    private val goalIndex: Map<String, String> = buildMap { goals.forEach { (k, v) -> v.forEach { put(it, k) } } }

    fun classConcept(internalName: String): String? = classIndex[internalName]
    fun goalConcept(internalName: String): String? = goalIndex[internalName]
    fun isMethod(concept: String, name: String) = methods[concept]?.contains(name) == true
    fun methodConcepts(name: String): List<String> = methods.filterValues { name in it }.keys.toList()

    /** Order matters: the first concept found walking up the hierarchy is the entity's base. */
    val entityBases = listOf(
        "Zombie", "AbstractSkeleton", "Spider", "EnderMan", "Creeper", "Monster", "TamableAnimal", "Animal", "AgeableMob",
        "WaterAnimal", "FlyingMob", "PathfinderMob", "Mob", "ThrowableItemProjectile", "Projectile", "LivingEntity", "Entity",
    )

    fun isMinecraft(internalName: String) = internalName.startsWith("net/minecraft/") || internalName.startsWith("com/mojang/")
}
