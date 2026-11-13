package com.example.fogwatcher.client;

import com.example.fogwatcher.entity.TheWatcher;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.ResourceLocation;

public final class JumpscareOverlay {
    private static final ResourceLocation FACE = new ResourceLocation("fogwatcher", "textures/gui/jumpscare.png");
    private static TheWatcher source;

    public static void trigger(TheWatcher watcher) { source = watcher; }

    public static void render(GuiGraphics graphics) {
        if (source != null) graphics.blit(FACE, 0, 0, 0, 0, 256, 256);
    }
}
