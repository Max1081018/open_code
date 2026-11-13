package com.example.fogwatcher.goal;

import net.minecraft.world.entity.PathfinderMob;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.player.Player;

/** Follows the player through the fog, never closer than the keep distance. */
public class StalkPlayerGoal extends Goal {
    private final PathfinderMob mob;
    private final double keepDistance;
    private Player target;

    public StalkPlayerGoal(PathfinderMob mob, double keepDistance) {
        this.mob = mob;
        this.keepDistance = keepDistance;
    }

    @Override
    public boolean canUse() {
        target = mob.level().getNearestPlayer(mob, 96.0);
        return target != null && mob.distanceToSqr(target) > 400.0;
    }

    @Override
    public void tick() {
        mob.getLookControl().setLookAt(target, 30.0f, 30.0f);
        if (mob.distanceToSqr(target) > 576.0) {
            mob.getNavigation().moveTo(target, 1.0);
        } else {
            mob.getNavigation().stop();
        }
    }
}
