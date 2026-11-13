package net.minecraft.world.entity.monster;
public abstract class Monster extends net.minecraft.world.entity.PathfinderMob { protected Monster(net.minecraft.world.entity.EntityType<? extends Monster> t, net.minecraft.world.level.Level l){super(t,l);} public static net.minecraft.world.entity.ai.attributes.AttributeSupplier.Builder createMonsterAttributes(){return null;} }
