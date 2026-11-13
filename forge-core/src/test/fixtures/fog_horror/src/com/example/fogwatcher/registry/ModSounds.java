package com.example.fogwatcher.registry;

import com.example.fogwatcher.FogWatcherMod;
import net.minecraft.resources.ResourceLocation;
import net.minecraft.sounds.SoundEvent;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class ModSounds {
    public static final DeferredRegister<SoundEvent> SOUNDS = DeferredRegister.create(ForgeRegistries.SOUND_EVENTS, FogWatcherMod.MODID);
    public static final RegistryObject<SoundEvent> WATCHER_AMBIENT = register("watcher_ambient");
    public static final RegistryObject<SoundEvent> WATCHER_SCREAM = register("watcher_scream");

    private static RegistryObject<SoundEvent> register(String name) {
        return SOUNDS.register(name, () -> SoundEvent.createVariableRangeEvent(new ResourceLocation(FogWatcherMod.MODID, name)));
    }
}
