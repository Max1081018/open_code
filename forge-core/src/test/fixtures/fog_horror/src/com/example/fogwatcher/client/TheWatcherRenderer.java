package com.example.fogwatcher.client;

import com.example.fogwatcher.entity.TheWatcher;
import net.minecraft.client.renderer.entity.EntityRendererProvider;
import software.bernie.geckolib.renderer.GeoEntityRenderer;

public class TheWatcherRenderer extends GeoEntityRenderer<TheWatcher> {
    public TheWatcherRenderer(EntityRendererProvider.Context ctx) { super(ctx, new WatcherModel()); }
}
