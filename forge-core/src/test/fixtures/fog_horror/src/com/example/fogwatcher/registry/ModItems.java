package com.example.fogwatcher.registry;

import com.example.fogwatcher.FogWatcherMod;
import net.minecraft.world.item.Item;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class ModItems {
    public static final DeferredRegister<Item> ITEMS = DeferredRegister.create(ForgeRegistries.ITEMS, FogWatcherMod.MODID);
    public static final RegistryObject<Item> FOG_ESSENCE = ITEMS.register("fog_essence", () -> new Item(new Item.Properties()));
}
