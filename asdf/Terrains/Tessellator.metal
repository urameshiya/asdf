//
//  Tessellator.metal
//  asdf
//
//  Created by Chinh Vu on 12/10/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

#include <metal_stdlib>
#import "../ShaderTypes.h"

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
