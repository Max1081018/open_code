package com.example.ghouls;

import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class Ghouls {
    public static final DeferredRegister<EntityType<?>> ENTITIES = DeferredRegister.create(ForgeRegistries.ENTITY_TYPES, "ghouls");
    public static final RegistryObject<EntityType<Ghoul>> GHOUL = ENTITIES.register("ghoul",
        () -> EntityType.Builder.of(Ghoul::new, MobCategory.MONSTER).sized(0.6f, 1.95f).build("ghoul"));
}
