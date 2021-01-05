//
//  Tessellator.metal
//  asdf
//
//  Created by Chinh Vu on 12/10/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

#include <metal_stdlib>
#import "../ShaderTypes.h"
#import "TerrainShaderTypes.h"

using namespace metal;

constant bool fc_isGenerateHeightMapPass [[ function_constant(0) ]];

typedef struct
{
    float4 position [[position]];
	float2 texCoord;
} ColorInOut;

struct TerrainVertexOut {
	float4 position [[ position ]];
	float worldHeight [[ function_constant(fc_isGenerateHeightMapPass) ]];
	float3 bary;
	half4 color;
};

vertex TerrainVertexOut terrain_vert
(
 const device TerrainVertexIn* vIn [[ buffer(0) ]],
 const device TerrainInstanceUniforms* iUniforms [[ buffer(1) ]],
 const device GlobalUniforms& gUniforms [[ buffer(2) ]],
 const texture2d<float, access::sample> noise [[ texture(0) ]],
 const uint instanceId [[ instance_id ]],
 const uint vId [[ vertex_id ]],
 const constant float4x4& depthViewProjectionMatrix [[ buffer(3), function_constant(fc_isGenerateHeightMapPass) ]]
)
{
	TerrainVertexOut vOut;
	
	constexpr sampler noiseSampler(mag_filter::nearest, min_filter::nearest, address::mirrored_repeat);
	
	float4 worldPosition;
	worldPosition.w = 1.0;
	worldPosition.xz = vIn[vId].basePosition.xz + iUniforms[instanceId].worldPosition;
	worldPosition.y = noise.sample(noiseSampler, worldPosition.xz / 512).r;
	
	if (fc_isGenerateHeightMapPass) {
		vOut.worldHeight = worldPosition.y;
		vOut.position = depthViewProjectionMatrix * worldPosition;
		vOut.position.xyz = float3(vOut.position.xz, 1.0);
	} else {
		vOut.position = gUniforms.camera.viewProjectionMatrix * worldPosition;
		
		vOut.bary = float3(vIn[vId].bary == uchar3(0, 1, 2));
	}

	return vOut;
}

fragment float terrain_height_frag(const TerrainVertexOut vOut [[ stage_in ]]) {
	return vOut.worldHeight;
}

fragment float4 terrain_frag(const TerrainVertexOut in [[ stage_in ]])
{
	float4 color(1,0,1,1);
	float width = 0.01; // line width, max 0.33
	float3 reducedRange = max(width - in.bary, 0) / width;
	float feathering = max3(reducedRange.x, reducedRange.y, reducedRange.z);
	
	return color * feathering;
}

constant float2 vRect[4] = {
	float2(-1.0, -1.0),
	float2(-1.0, 1.0),
	float2(1.0, -1.0),
	float2(1.0, 1.0)
};

constant float2 uvRect[4] = {
	float2(0.0, 0.0),
	float2(0.0, 1.0),
	float2(1.0, 0.0),
	float2(1.0, 1.0)
};

constant bool fc_withTransform [[ function_constant(1) ]];

vertex ColorInOut hud_vertex(uint vid [[ vertex_id ]],
							 const device float4x4& modelViewMatrix [[ buffer(0), function_constant(fc_withTransform) ]],
							 const device GlobalUniforms& globalUniforms [[ buffer(1), function_constant(fc_withTransform) ]]) {
	ColorInOut out;
	

	if (fc_withTransform) {
		out.position = globalUniforms.camera.viewProjectionMatrix * modelViewMatrix * float4(vRect[vid], 0.0, 1.0).xzyw;
	} else {
		out.position = float4(vRect[vid] * 0.3 + 0.2, 0.5, 1.0);
	}
	out.texCoord = uvRect[vid];
	
	return out;
};

fragment float4 hud_fragment(ColorInOut in [[stage_in]],
							 texture2d<half> colorMap     [[ texture(0) ]],
							 const device float& carHeight [[ buffer(0) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    half4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);

    return float4(carHeight - colorSample);
}
