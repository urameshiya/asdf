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
	var wheelTexture: MTLTexture
	var wheelDepthTexture: MTLTexture
	var pos = float3(12, 1, 17)
	var rot = 0.3 as Float
	var pipeline_hud: MTLRenderPipelineState
	var pipeline_world: MTLRenderPipelineState
	var pipeline_find_max: MTLComputePipelineState
	var pipeline_ground_contact: MTLRenderPipelineState
	var pipeline_contact_depth: MTLDepthStencilState
	var dimX: Float = 30
	var dimZ: Float = 20
	var yOffsetBuffer: TypedBuffer<Float>
	
	init(context: RenderingContext) {
		let texDesc = MTLTextureDescriptor()
		texDesc.width = 512
		texDesc.height = 512
		texDesc.pixelFormat = .r32Float
		texDesc.storageMode = .managed
		texDesc.textureType = .type2D
		texDesc.usage = [.shaderRead, .renderTarget]
		
		terrainHeightAtWheel = context.device.makeTexture(descriptor: texDesc)!
		wheelTexture = context.device.makeTexture(descriptor: texDesc)!
		
		texDesc.usage = [.renderTarget]
		texDesc.storageMode = .private
		texDesc.pixelFormat = .depth32Float
		wheelDepthTexture = context.device.makeTexture(descriptor: texDesc)!
		
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
		pipelineDesc.vertexFunction = context.defaultLibrary.makeFunction(name: "wheel_mesh_vertex")!
		pipelineDesc.fragmentFunction = context.defaultLibrary.makeFunction(name: "simple_fragment")!
		pipeline_world = try! context.device.makeRenderPipelineState(descriptor: pipelineDesc)
		
		let computeDesc = MTLComputePipelineDescriptor()
		computeDesc.computeFunction = context.defaultLibrary.makeFunction(name: "find_max")!
		
		pipeline_find_max = try! context.device.makeComputePipelineState(descriptor: computeDesc, options: [], reflection: nil)
		
		yOffsetBuffer = .init(count: 1, allocator: { (size) -> MTLBuffer in
			context.device.makeBuffer(length: size, options: [.storageModeShared])!
		})
		
		let contact_fc = MTLFunctionConstantValues()
		contact_fc.setConstantValue(&yes, type: .bool, index: 0)
		pipelineDesc.colorAttachments[0].pixelFormat = .r32Float
		pipelineDesc.depthAttachmentPixelFormat = .depth32Float
		pipelineDesc.stencilAttachmentPixelFormat = .invalid
		pipelineDesc.vertexFunction = try! context.defaultLibrary.makeFunction(name: "contact_surface_vertex", constantValues: contact_fc)
		pipelineDesc.fragmentFunction = try! context.defaultLibrary.makeFunction(name: "terrain_height_frag", constantValues: contact_fc)
		pipeline_ground_contact = try! context.device.makeRenderPipelineState(descriptor: pipelineDesc)
				
		let depthPipelineDesc = MTLDepthStencilDescriptor()
		depthPipelineDesc.isDepthWriteEnabled = true
		depthPipelineDesc.depthCompareFunction = .less
		
		pipeline_contact_depth = context.device.makeDepthStencilState(descriptor: depthPipelineDesc)!
		
		fillWheelMesh(context: context)
	}
	
	func sceneToObjectSpaceMatrix() -> matrix_float4x4 {
		let rotation = matrix4x4_rotation(radians: -rot, axis: .init(x: 0, y: 1, z: 0))
		let translation = matrix4x4_translation(-pos.x, -30, -pos.z)
		let remap = matrix_remap_xz(width: dimX, height: dimZ)
		
		return remap * rotation * translation
	}
	
	func render(encoder: MTLRenderCommandEncoder, globalUniforms: TripleBuffer<GlobalUniforms>, camera: Camera) {
		encoder.pushDebugGroup("World car")
		let scale = matrix_scale(dimX / 2, 30, dimZ / 2)
		let rotation = matrix4x4_rotation(radians: rot, axis: .init(x: 0, y: 1, z: 0))
		var translation = matrix4x4_translation(pos.x, pos.y, pos.z) * rotation * scale
		encoder.setRenderPipelineState(pipeline_world)
		encoder.setVertexBuffer(vBuffer, index: 0)
		encoder.setVertexBytes(&translation, length: MemoryLayout.size(ofValue: translation), index: 1)
		encoder.setVertexBuffer(globalUniforms, index: 2)
		encoder.setVertexBuffer(yOffsetBuffer, offset: 0, index: 3)
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0)
		encoder.popDebugGroup()
	}
	
	func findHighestHeight() {
		
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
		
		do { // make contact map
			let renderpass = MTLRenderPassDescriptor()
			renderpass.colorAttachments[0].texture = wheelTexture
			renderpass.depthAttachment.texture = wheelDepthTexture
			
			let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderpass)!
			encoder.label = "Wheel contact"
			encoder.setRenderPipelineState(pipeline_ground_contact)
			encoder.setVertexBuffer(vBuffer, index: 0)
			var transform = matrix_remap_xz(width: dimX, height: dimZ) * modelTransform()
			encoder.setVertexBytes(&transform, length: 64, index: 1)
			encoder.setDepthStencilState(pipeline_contact_depth)
			encoder.drawIndexedPrimitives(type: .triangle,
										  indexCount: indexBuffer.elementCount,
										  indexType: .uint32,
										  indexBuffer: indexBuffer.buffer,
										  indexBufferOffset: 0)
			encoder.endEncoding()
		}
		
		
		terrains.generateHeightMap(buffer: commandBuffer,
								   intoTexture: terrainHeightAtWheel,
								   sceneToObjectSpaceTransform: sceneToObjectSpaceMatrix(),
								   globalUniforms: globalUniforms)
		
		let encoder = commandBuffer.makeComputeCommandEncoder()!
		encoder.setComputePipelineState(pipeline_find_max)
		encoder.setTexture(terrainHeightAtWheel, index: 0)
		encoder.setTexture(wheelTexture, index: 1)
		encoder.setBuffer(yOffsetBuffer.buffer, offset: 0, index: 0)
		
		let gridsize = MTLSize(width: terrainHeightAtWheel.width / Int(FIND_MAX_SIZE),
							   height: terrainHeightAtWheel.height / Int(FIND_MAX_SIZE),
							   depth: 1)
		let w = pipeline_find_max.threadExecutionWidth
		let tgSize = MTLSize(width: w, height: pipeline_find_max.maxTotalThreadsPerThreadgroup / w, depth: 1)
		encoder.dispatchThreads(gridsize, threadsPerThreadgroup: tgSize)
		
		encoder.endEncoding()
	}
	
	func modelTransform() -> float4x4 {
		return matrix4x4_rotation(radians: rot, axis: .init(0, 1, 0)) * matrix_scale(dimX / 2, 30, dimZ / 2)
	}
	
	var vBuffer: TypedBuffer<Float>!
	var indexBuffer: TypedBuffer<UInt32>!
	
	func fillWheelMesh(context: RenderingContext) {
		let vertices: [Float] = [
			0.5, 0, 0,
			0, 0.5, 0,
			0.5, 1, 0,
			1, 0.5, 0,
			0.5, 0, 1,
			0, 0.5, 1,
			0.5, 1, 1,
			1, 0.5, 1,
		]
		
		let faces: [UInt32] = [
			0, 1, 3, 2,
			4, 5, 7, 6,
			0, 1, 4, 5,
			1, 2, 5, 6,
			2, 3, 6, 7,
			3, 0, 7, 4,
		]
		
		let triFaces = quadsToTriangles(quadFaces: faces)
		
		vBuffer = .init(count: vertices.count, allocator: { (size) -> MTLBuffer in
			context.device.makeBuffer(length: size, options: [.storageModeShared])!
		})
		
		indexBuffer = .init(count: triFaces.count, allocator: { (size) -> MTLBuffer in
			context.device.makeBuffer(length: size, options: [.storageModeShared])!
		})
		
		vBuffer.fill(with: vertices.map({ $0 * 2 - 1 }))
		indexBuffer.fill(with: triFaces)
	}
	
	private func quadsToTriangles(quadFaces: [UInt32]) -> [UInt32] {
		assert(quadFaces.count % 4 == 0)
		
		var newFaces = [UInt32]()
		for i in stride(from: 0, to: quadFaces.count, by: 4) {
			newFaces.append(contentsOf: [quadFaces[i], quadFaces[i + 1], quadFaces[i + 2]])
			newFaces.append(contentsOf: [quadFaces[i + 1], quadFaces[i + 2], quadFaces[i + 3]])
		}
		assert(newFaces.count / 3 == quadFaces.count / 4 * 2)
		return newFaces
	}
}

//class BasicMesh {
//	var vertexBuffer: TypedBuffer<Float>
//	var indexBuffer: TypedBuffer<UInt32>
//
//	init(vertices: [Float], indices: [UInt32], primitive: MTLPrimitiveType) {
//
//	}
//}

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
