package com.example.fogwatcher.registry;

import com.example.fogwatcher.FogWatcherMod;
import com.example.fogwatcher.entity.TheWatcher;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.MobCategory;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class ModEntities {
    public static final DeferredRegister<EntityType<?>> ENTITIES = DeferredRegister.create(ForgeRegistries.ENTITY_TYPES, FogWatcherMod.MODID);
    public static final RegistryObject<EntityType<TheWatcher>> THE_WATCHER = ENTITIES.register("the_watcher",
        () -> EntityType.Builder.of(TheWatcher::new, MobCategory.MONSTER).sized(0.7f, 2.9f).build("the_watcher"));
}
