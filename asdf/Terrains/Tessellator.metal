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
	bool collided;
};

TerrainVertexOut generateWorldHeight(float4 worldPosition, float4x4 xyProjectionMatrix, float depthValue) {
	TerrainVertexOut out;
	out.worldHeight = worldPosition.y;
	out.position = xyProjectionMatrix * worldPosition;
	out.position.xyz = float3(out.position.xz, depthValue);
	return out;
}

vertex TerrainVertexOut terrain_vert
(
 const device TerrainVertexIn* vIn [[ buffer(0) ]],
 const device GlobalUniforms& gUniforms [[ buffer(1) ]],
 const device uint& instance_size [[ buffer(2) ]],
 const uint vId [[ vertex_id ]],
 const uint instanceId [[ instance_id ]]
)
{
	TerrainVertexOut vOut;
	TerrainVertexIn vert = vIn[vId + instanceId * instance_size];
	vOut.position = gUniforms.camera.viewProjectionMatrix * float4(vert.position, 1.0);
		
	vOut.bary = float3(vert.bary == uchar3(0, 1, 2));
	vOut.collided = vert.collided;
	return vOut;
}

kernel void populate_terrain
(
 const device TerrainVertexIn* baseVertices [[ buffer(0) ]],
 const device TerrainInstanceUniforms* iUniforms [[ buffer(1) ]],
 device TerrainVertexIn* vOut [[ buffer(2) ]],
 const texture2d<float, access::sample> noise [[ texture(0) ]],
 uint2 tid [[ thread_position_in_grid ]]
)
{
	constexpr sampler noiseSampler(mag_filter::nearest, min_filter::nearest, address::mirrored_repeat);
	
	uint vId = tid.x;
	uint chunkId = tid.y;
	float3 worldPosition;
	worldPosition.xz = baseVertices[vId].position.xz + iUniforms[chunkId].worldPosition;
	worldPosition.y = noise.sample(noiseSampler, worldPosition.xz / 512).r;
	
	TerrainVertexIn out;
	out.position = worldPosition;
	out.bary = baseVertices[vId].bary;
	vOut[iUniforms[chunkId].chunkOffset + vId] = out;
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
	
	if (in.collided) {
		return float4(0, 1, 0, 1);
	}
	
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
							 const device float& terrainYOffset [[ buffer(2) ]],
							 const device GlobalUniforms& globalUniforms [[ buffer(1), function_constant(fc_withTransform) ]]) {
	ColorInOut out;
	

	if (fc_withTransform) {
		out.position = modelViewMatrix * float4(vRect[vid], 0.0, 1.0).xzyw;
		out.position.y += terrainYOffset;
		out.position = globalUniforms.camera.viewProjectionMatrix * out.position;
	} else {
		out.position = float4(vRect[vid] * 0.3 + 0.2, 0.5, 1.0);
	}
	out.texCoord = uvRect[vid];
	
	return out;
};

void atomic_max(device float* maxValue, float val) {
	if (val >= 0) {
		atomic_fetch_max_explicit((device atomic_int*) maxValue, as_type<int>(val), memory_order_relaxed);
	} else {
		atomic_fetch_min_explicit((device atomic_uint*) maxValue, as_type<uint>(val), memory_order_relaxed);
	}
}

fragment float4 hud_fragment(ColorInOut in [[stage_in]],
							 const texture2d<float> colorMap     [[ texture(0) ]],
							 const texture2d<float> contactMap [[ texture(1) ]],
							 device float& maxHeight [[ buffer(1) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    float4 colorSample   = colorMap.sample(colorSampler, in.texCoord.xy);
//	atomic_max(&maxHeight, colorSample.r);
	float4 contactPoint = contactMap.sample(colorSampler, in.texCoord.xy);
	return float4(contactPoint.r - colorSample.r);
}

kernel void find_max(texture2d<float, access::read> terrainMap [[ texture(0) ]],
					 texture2d<float, access::read> contactMap [[ texture(1) ]],
					 device float* max_value [[ buffer(0) ]],
					 const uint2 tid [[ thread_position_in_grid ]])
{
	float local_max = -9999;
	for (uint x = tid.x * FIND_MAX_SIZE; x < (tid.x + 1) * FIND_MAX_SIZE && x < terrainMap.get_width(); x++) {
		for (uint y = tid.y * FIND_MAX_SIZE; y < (tid.y + 1) * FIND_MAX_SIZE && y < terrainMap.get_height(); y++) {
			float terrainY = terrainMap.read(uint2(x, y)).r;
			float contactY = contactMap.read(uint2(x, y)).r;
			local_max = max(terrainY - contactY, local_max);
		}
	}
	atomic_max(max_value, local_max);
}

vertex TerrainVertexOut contact_surface_vertex(const device packed_float3* vIn [[ buffer(0) ]],
											   const device float4x4& modelTransform [[ buffer(1) ]],
											   const uint vid [[ vertex_id ]])
{
	TerrainVertexOut out;
	out.position = modelTransform * float4(vIn[vid], 1.0);
	out.worldHeight = out.position.y;
	out.position.xzy = out.position.xyz;
	out.position.z = (out.position.z + 1000) * 0.001;
	return out;
}

vertex ColorInOut wheel_mesh_vertex(const device packed_float3* vIn [[ buffer(0) ]],
								const device float4x4& modelTransform [[ buffer(1) ]],
								const device GlobalUniforms& globalUniforms [[ buffer(2) ]],
								const device float& yOffset [[ buffer(3) ]],
								const uint vid [[ vertex_id] ])
{
	float4 worldSpace = modelTransform * float4(vIn[vid], 1.0);
	worldSpace.y += yOffset;
	
	ColorInOut out;
	out.position = globalUniforms.camera.viewProjectionMatrix * worldSpace;
	out.texCoord = float2(float(vid % 3) / 3);
	return out;
}

fragment float4 simple_fragment(const ColorInOut in [[ stage_in ]],
								const device bool& collided [[ buffer(0) ]]) {
	return collided ? float4(1, 0, 0, 1) : float4(in.texCoord, 0, 1.0);
}
