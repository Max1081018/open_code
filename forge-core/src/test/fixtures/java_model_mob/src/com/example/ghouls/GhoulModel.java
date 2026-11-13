package com.example.ghouls;

import net.minecraft.client.model.geom.PartPose;
import net.minecraft.client.model.geom.builders.CubeDeformation;
import net.minecraft.client.model.geom.builders.CubeListBuilder;
import net.minecraft.client.model.geom.builders.LayerDefinition;
import net.minecraft.client.model.geom.builders.MeshDefinition;
import net.minecraft.client.model.geom.builders.PartDefinition;

public class GhoulModel {
    public static LayerDefinition createBodyLayer() {
        MeshDefinition mesh = new MeshDefinition();
        PartDefinition root = mesh.getRoot();
        PartDefinition body = root.addOrReplaceChild("body", CubeListBuilder.create().texOffs(16, 16).addBox(-4.0f, 0.0f, -2.0f, 8.0f, 12.0f, 4.0f), PartPose.offset(0.0f, 0.0f, 0.0f));
        body.addOrReplaceChild("head", CubeListBuilder.create().texOffs(0, 0).addBox(-4.0f, -8.0f, -4.0f, 8.0f, 8.0f, 8.0f, new CubeDeformation(0.5f)), PartPose.offset(0.0f, 0.0f, 0.0f));
        root.addOrReplaceChild("right_arm", CubeListBuilder.create().texOffs(40, 16).addBox(-3.0f, -2.0f, -2.0f, 4.0f, 12.0f, 4.0f), PartPose.offsetAndRotation(-5.0f, 2.0f, 0.0f, -1.5f, 0.0f, 0.0f));
        root.addOrReplaceChild("left_arm", CubeListBuilder.create().texOffs(40, 16).mirror().addBox(-1.0f, -2.0f, -2.0f, 4.0f, 12.0f, 4.0f), PartPose.offsetAndRotation(5.0f, 2.0f, 0.0f, -1.5f, 0.0f, 0.0f));
        root.addOrReplaceChild("right_leg", CubeListBuilder.create().texOffs(0, 16).addBox(-2.0f, 0.0f, -2.0f, 4.0f, 12.0f, 4.0f), PartPose.offset(-1.9f, 12.0f, 0.0f));
        root.addOrReplaceChild("left_leg", CubeListBuilder.create().texOffs(0, 16).mirror().addBox(-2.0f, 0.0f, -2.0f, 4.0f, 12.0f, 4.0f), PartPose.offset(1.9f, 12.0f, 0.0f));
        return LayerDefinition.create(mesh, 64, 64);
    }
}
