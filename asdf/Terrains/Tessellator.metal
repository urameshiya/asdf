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

typedef struct
{
    float4 position [[position]];
	half4 color;
} ColorInOut;

vertex ColorInOut tess_vertex(constant packed_float3* vIn [[ buffer(BufferIndexMeshPositions) ]],
							  constant Uniforms& uniforms [[ buffer(BufferIndexUniforms) ]],
							  uint vId [[ vertex_id ]])
{
	ColorInOut out;
	out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * float4(vIn[vId], 1);
	uint3 offset = uint3(0, 1, 2);
	out.color = half4(half3((offset + vId) % 3) / 3.0, 1);
	return out;
}

fragment half4 tess_frag(ColorInOut in [[ stage_in ]])
{
	return in.color;
}

struct TerrainVertexOut {
	float4 position [[ position ]];
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
 const uint vId [[ vertex_id ]]
)
{
	TerrainVertexOut vOut;
	
	constexpr sampler noiseSampler(address::mirrored_repeat);
	
	float4 worldPosition;
	worldPosition.w = 1.0;
	worldPosition.xz = vIn[vId].basePosition.xz + iUniforms[instanceId].worldPosition;
	worldPosition.y = noise.sample(noiseSampler, worldPosition.xz / 512).r;
	vOut.position = gUniforms.camera.viewProjectionMatrix * worldPosition;
	
	vOut.bary = float3(vIn[vId].bary == uchar3(0, 1, 2));
	
	uint3 offset(0, 1, 2);
	vOut.color = half4(half3((offset + vId) % 3) / 3.0, 1);
	return vOut;
}

fragment float4 terrain_frag(const TerrainVertexOut in [[ stage_in ]])
{
	float4 color(1,0,1,1);
	float width = 0.01; // line width, max 0.33
	float3 reducedRange = max(width - in.bary, 0) / width;
	float feathering = max3(reducedRange.x, reducedRange.y, reducedRange.z);
	
	return color * feathering;
}
