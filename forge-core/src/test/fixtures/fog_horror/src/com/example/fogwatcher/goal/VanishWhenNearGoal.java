package com.example.fogwatcher.goal;

import com.example.fogwatcher.registry.ModSounds;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.world.entity.Mob;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.player.Player;

/** Disappears in a puff of smoke when the player gets within 8 blocks before it has a target. */
public class VanishWhenNearGoal extends Goal {
    private final Mob mob;
    public VanishWhenNearGoal(Mob mob) { this.mob = mob; }

    @Override
    public boolean canUse() {
        Player player = mob.level().getNearestPlayer(mob, 64.0);
        return player != null && mob.getTarget() == null && mob.distanceToSqr(player) < 64.0;
    }

    @Override
    public void start() {
        mob.playSound(ModSounds.WATCHER_SCREAM.get(), 1.0f, 0.6f);
        mob.level().addParticle(ParticleTypes.SMOKE, mob.getX(), mob.getY() + 1.0, mob.getZ(), 0, 0.05, 0);
        mob.discard();
    }
}
