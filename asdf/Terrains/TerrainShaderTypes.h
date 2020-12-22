//
//  TerrainShaderTypes.h
//  asdf
//
//  Created by Chinh Vu on 12/18/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

#ifndef TerrainShaderTypes_h
#define TerrainShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#import <simd/simd.h>

#ifdef __METAL_VERSION__
#else
typedef struct {
	float x, y, z;
} packed_float3;
typedef simd_float2 float2;
#endif

struct TerrainVertexIn {
	packed_float3 basePosition;
	uint8_t bary;
};

struct TerrainInstanceUniforms {
	float2 worldPosition;
};

typedef struct {
	matrix_float4x4 viewMatrix;
	matrix_float4x4 projectionMatrix;
	matrix_float4x4 viewProjectionMatrix;
} CameraUniforms;

struct GlobalUniforms {
	CameraUniforms camera;
};

#endif /* TerrainShaderTypes_h */
