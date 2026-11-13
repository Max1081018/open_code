package com.example.fogwatcher.entity;

import com.example.fogwatcher.goal.StalkPlayerGoal;
import com.example.fogwatcher.goal.VanishWhenNearGoal;
import com.example.fogwatcher.registry.ModSounds;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.sounds.SoundEvent;
import net.minecraft.world.effect.MobEffectInstance;
import net.minecraft.world.effect.MobEffects;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.ai.attributes.AttributeSupplier;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.entity.ai.goal.FloatGoal;
import net.minecraft.world.entity.ai.goal.Goal;
import net.minecraft.world.entity.ai.goal.LookAtPlayerGoal;
import net.minecraft.world.entity.ai.goal.MeleeAttackGoal;
import net.minecraft.world.entity.ai.goal.target.NearestAttackableTargetGoal;
import net.minecraft.world.entity.monster.Monster;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import software.bernie.geckolib.animatable.GeoEntity;

/** A figure in the fog: watches from afar, freezes when looked at, vanishes up close, hunts at night. */
public class TheWatcher extends Monster implements GeoEntity {
    public TheWatcher(EntityType<? extends Monster> type, Level level) {
        super(type, level);
    }

    public static AttributeSupplier.Builder createAttributes() {
        return Monster.createMonsterAttributes()
            .add(Attributes.MAX_HEALTH, 80.0)
            .add(Attributes.MOVEMENT_SPEED, 0.32)
            .add(Attributes.ATTACK_DAMAGE, 9.0)
            .add(Attributes.FOLLOW_RANGE, 64.0);
    }

    @Override
    protected void registerGoals() {
        this.goalSelector.addGoal(0, new FloatGoal(this));
        this.goalSelector.addGoal(1, new FreezeWhenWatchedGoal(this));
        this.goalSelector.addGoal(2, new VanishWhenNearGoal(this));
        this.goalSelector.addGoal(3, new StalkPlayerGoal(this, 24.0));
        this.goalSelector.addGoal(4, new MeleeAttackGoal(this, 1.2, false));
        this.goalSelector.addGoal(5, new LookAtPlayerGoal(this, Player.class, 32.0f));
        this.targetSelector.addGoal(1, new NearestAttackableTargetGoal<>(this, Player.class, true));
    }

    @Override
    public void tick() {
        super.tick();
        if (this.level().isNight()) {
            Player player = this.level().getNearestPlayer(this, 16.0);
            if (player != null) {
                player.addEffect(new MobEffectInstance(MobEffects.DARKNESS, 100, 0));
            }
            this.level().addParticle(ParticleTypes.ASH, getX(), getY() + 1.5, getZ(), 0, 0, 0);
        }
    }

    @Override
    public boolean removeWhenFarAway(double distance) {
        return false;
    }

    @Override
    protected SoundEvent getAmbientSound() {
        return ModSounds.WATCHER_AMBIENT.get();
    }

    @Override
    public boolean doHurtTarget(Entity target) {
        this.playSound(ModSounds.WATCHER_SCREAM.get(), 2.0f, 1.0f);
        return super.doHurtTarget(target);
    }

    /** Stands still while the player looks straight at it. */
    static class FreezeWhenWatchedGoal extends Goal {
        private final TheWatcher mob;
        FreezeWhenWatchedGoal(TheWatcher mob) { this.mob = mob; }

        @Override
        public boolean canUse() {
            Player player = mob.level().getNearestPlayer(mob, 48.0);
            if (player == null) return false;
            Vec3 look = player.getViewVector(1.0f).normalize();
            Vec3 toMob = mob.getEyePosition().subtract(player.getEyePosition()).normalize();
            return look.dot(toMob) > 0.95 && player.hasLineOfSight(mob);
        }

        @Override
        public void tick() {
            mob.getNavigation().stop();
            mob.setDeltaMovement(0, 0, 0);
        }
    }
}
