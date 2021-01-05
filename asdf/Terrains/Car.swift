//
//  Car.swift
//  asdf
//
//  Created by Chinh Vu on 12/23/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation
import MetalKit

class Car {
	var terrainHeightAtWheel: MTLTexture
	var pos = float3(12, 1, 17)
	var rot = 0.0 as Float
	var pipeline_hud: MTLRenderPipelineState
	var pipeline_world: MTLRenderPipelineState
	var width: Float = 30
	var height: Float = 20
	
	init(context: RenderingContext) {
		let texDesc = MTLTextureDescriptor()
		texDesc.width = 512
		texDesc.height = 512
		texDesc.pixelFormat = .r32Float
		texDesc.storageMode = .managed
		texDesc.textureType = .type2D
		texDesc.usage = [.shaderRead, .renderTarget]
		
		terrainHeightAtWheel = context.device.makeTexture(descriptor: texDesc)!
		
		let constantValues = MTLFunctionConstantValues()
		var yes = true
		var no = false
		constantValues.setConstantValue(&no, type: .bool, withName: "fc_withTransform")
		let pipelineDesc = MTLRenderPipelineDescriptor()
		pipelineDesc.vertexFunction = try! context.defaultLibrary.makeFunction(name: "hud_vertex", constantValues: constantValues)
		pipelineDesc.fragmentFunction = context.defaultLibrary.makeFunction(name: "hud_fragment")!
		pipelineDesc.colorAttachments[0].pixelFormat = context.colorPixelFormat
		pipelineDesc.depthAttachmentPixelFormat = context.depthPixelFormat
		pipelineDesc.stencilAttachmentPixelFormat = context.stencilPixelFormat

		pipeline_hud = try! context.device.makeRenderPipelineState(descriptor: pipelineDesc)
		
		constantValues.setConstantValue(&yes, type: .bool, withName: "fc_withTransform")
		pipelineDesc.vertexFunction = try! context.defaultLibrary.makeFunction(name: "hud_vertex", constantValues: constantValues)
		pipeline_world = try! context.device.makeRenderPipelineState(descriptor: pipelineDesc)
	}
	
	func sceneToObjectSpaceMatrix() -> matrix_float4x4 {
		let rotation = matrix4x4_rotation(radians: -rot, axis: .init(x: 0, y: 1, z: 0))
		let translation = matrix4x4_translation(-pos.x, -30, -pos.z)
		let remap = matrix_remap_xz(width: width, height: height)
		
		return remap * rotation * translation
	}
	
	func render(encoder: MTLRenderCommandEncoder, globalUniforms: TripleBuffer<GlobalUniforms>, camera: Camera) {
		encoder.setRenderPipelineState(pipeline_hud)
		encoder.setFragmentTexture(terrainHeightAtWheel, index: 0)
		var carHeight = pos.y
		encoder.setFragmentBytes(&carHeight, length: MemoryLayout<Float>.size, index: 0)
		
		encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		
		encoder.pushDebugGroup("World car")
		let scale = matrix_scale(width / 2, 1, height / 2)
		let rotation = matrix4x4_rotation(radians: rot, axis: .init(x: 0, y: 1, z: 0))
		var translation = matrix4x4_translation(pos.x, pos.y, pos.z) * rotation * scale
		encoder.setRenderPipelineState(pipeline_world)
		encoder.setVertexBytes(&translation, length: MemoryLayout.size(ofValue: translation), index: 0)
		encoder.setVertexBuffer(globalUniforms, index: 1)
		encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
		encoder.popDebugGroup()
	}
	
	func update(
		commandBuffer: MTLCommandBuffer,
		globalUniforms: TripleBuffer<GlobalUniforms>,
		terrains: ChunkRenderer,
		camera: Camera
	) {
//		pos.x = camera.x
//		pos.y = camera.y - 4
//		pos.z = camera.z - 50
		terrains.generateHeightMap(buffer: commandBuffer,
								   intoTexture: terrainHeightAtWheel,
								   sceneToObjectSpaceTransform: sceneToObjectSpaceMatrix(),
								   globalUniforms: globalUniforms)
	}
}

struct Rect {
	
}

func matrix_remap_xz(width: Float, height: Float) -> matrix_float4x4 {
	// -halfWidth...halfWidth. -> -1...1
	
    let zs = 2 / height
    let xs = 2 / width
    return matrix_float4x4.init(columns:(vector_float4(xs,  0, 0,   0),
                                         vector_float4( 0, 1, 0,   0),
                                         vector_float4( 0,  0, -zs,  0),
                                         vector_float4( 0,  0, 0, 1)))
}

func matrix_scale(_ x: Float, _ y: Float, _ z: Float) -> matrix_float4x4 {
	return matrix_float4x4.init(columns:(vector_float4(x,  0, 0,   0),
										 vector_float4( 0, y, 0,   0),
										 vector_float4( 0,  0, z,  0),
										 vector_float4( 0,  0, 0, 1)))
}
