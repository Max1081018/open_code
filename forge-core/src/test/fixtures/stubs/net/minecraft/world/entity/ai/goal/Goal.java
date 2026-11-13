package net.minecraft.world.entity.ai.goal;
public abstract class Goal { public enum Flag { MOVE, LOOK, JUMP, TARGET } public abstract boolean canUse(); public boolean canContinueToUse(){return canUse();} public void start(){} public void stop(){} public void tick(){} public void setFlags(java.util.EnumSet<Flag> f){} }
