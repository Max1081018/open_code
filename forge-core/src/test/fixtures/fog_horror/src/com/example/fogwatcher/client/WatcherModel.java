package com.example.fogwatcher.client;

import com.example.fogwatcher.entity.TheWatcher;
import net.minecraft.resources.ResourceLocation;
import software.bernie.geckolib.model.DefaultedEntityGeoModel;

public class WatcherModel extends DefaultedEntityGeoModel<TheWatcher> {
    public WatcherModel() { super(new ResourceLocation("fogwatcher", "the_watcher")); }
}
