package com.example.badapis.mixin;

import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(targets = "net.minecraft.client.gui.screens.TitleScreen")
public class TitleScreenMixin {
    @Inject(method = "init")
    private void onInit(CallbackInfo ci) {}
}
