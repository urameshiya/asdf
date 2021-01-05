//
//  ChunkRenderer.swift
//  asdf
//
//  Created by Chinh Vu on 12/15/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Metal

class ChunkRenderer {
	let renderDistance: Int = 2
	let renderedChunks = [(x: Int, z: Int)]()
	var renderCenter: (x: Int, z: Int) = (-10, -10)
	let chunkSize: Float = 100
	let tessellator = TriangleTessellator(levelCount: 30)
	let vertexBuffer: TypedBuffer<TerrainVertexIn>
	let indexBuffer: TypedBuffer<UInt32>
	var instanceUniformsBuffer: TripleBuffer<TerrainInstanceUniforms>
	let renderPipeline: MTLRenderPipelineState
	let areaHeightMapPipeline: MTLRenderPipelineState
	let perlinTexture: MTLTexture
	let instanceCount: Int
	
	init?(context: RenderingContext) {
		let device = context.device
		
		do {
			renderPipeline = try ChunkRenderer.makeRenderPipeline(context: context)
			areaHeightMapPipeline = try	ChunkRenderer.makeAreaHeightMapPipeline(ctx: context)
		} catch {
			print("Cannot compile render pipeline. Error: \(error)")
			return nil
		}
		
		// generate base instance
		let minX: Float = 0
		let maxX: Float = chunkSize
		let minZ: Float = 0
		let maxZ: Float = chunkSize
		let preVerts = [
			minX, 0, minZ,
			minX, 0, maxZ,
			maxX, 0, minZ,
			maxX, 0, maxZ,
		]
		let preIndices: [UInt32] = [
			0, 1, 2,
			1, 3, 2
		]
		
		vertexBuffer = TypedBuffer(count: tessellator.vTotal * 2) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		indexBuffer = TypedBuffer(count: tessellator.patchCount * 3 * 2) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		tessellator.tessellate(vertices: preVerts,
							   indices: preIndices,
							   outPositions: .init(vertexBuffer.bufferPointer().accessing(\.basePosition)),
							   outIndices: .init(indexBuffer.bufferPointer()),
							   outBarys: .init(vertexBuffer.bufferPointer().accessing(\.bary)))
		
		let side = renderDistance * 2 + 1
		instanceCount = side * side
		
		instanceUniformsBuffer = TripleBuffer(count: instanceCount) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		let perlinSize = MTLSize(width: 512, height: 512, depth: 1)
		let texDesc = MTLTextureDescriptor()
		texDesc.textureType = .type2D
		texDesc.pixelFormat = .r32Float
		texDesc.width = perlinSize.width
		texDesc.height = perlinSize.height
		texDesc.usage = .shaderRead
		texDesc.storageMode = .private
				
		perlinTexture = device.makeTexture(descriptor: texDesc)!
		
		// Generate perlin noise map and copy to gpu texture
		let bufferCount = perlinSize.width * perlinSize.height
		let perlinTempBuffer = TypedBuffer<Float>(count: bufferCount) { size in
			device.makeBuffer(length: size, options: [.storageModeShared])!
		}
		let noiseValues = perlinTempBuffer.bufferPointer()
		let noise = PerlinNoise2D()
		for x in 0..<perlinSize.width {
			for y in 0..<perlinSize.height {
				let coord = simd_float2(Float(x) / 37, Float(y) / 37)
				let noise = noise.at(coord)
				noiseValues[x * perlinSize.width + y] = noise * 20
			}
		}
		let commandBuffer = context.commandQueue.makeCommandBuffer()!
		let blit = commandBuffer.makeBlitCommandEncoder()!
		blit.copy(from: perlinTempBuffer, to: perlinTexture)
		blit.endEncoding()
		commandBuffer.commit()
		
	}
	
	/// Recalculate which chunks need to be rendered
	func update(camera: Camera) {
		let chunkX = Int(floor(camera.x / chunkSize))
		let chunkZ = Int(floor(camera.z / chunkSize))
		
		if (chunkX, chunkZ) == renderCenter {
			return
		}
		
		let uniforms = instanceUniformsBuffer.currentBufferPointer()
		
		var instanceId = 0
		for x in -renderDistance...renderDistance {
			for z in -renderDistance...renderDistance {
				uniforms[instanceId] = generateChunkUniforms(chunkX: chunkX + x, chunkZ: chunkZ + z)
				instanceId += 1
			}
		}
		assert(instanceId == instanceCount)
		
		instanceUniformsBuffer.commitBuffer()
		
		renderCenter = (chunkX, chunkZ)
	}
	
	func render(encoder: MTLRenderCommandEncoder, globalUniforms: TripleBuffer<GlobalUniforms>) {
		encoder.setRenderPipelineState(renderPipeline)
		encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
		encoder.setVertexBuffer(instanceUniformsBuffer, index: 1)
		encoder.setVertexBuffer(globalUniforms, index: 2)
		encoder.setVertexTexture(perlinTexture, index: 0)
		
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0,
									  instanceCount: instanceCount)
	}
	
	func generateHeightMap(
		buffer: MTLCommandBuffer,
		intoTexture texture: MTLTexture,
		sceneToObjectSpaceTransform: matrix_float4x4,
		globalUniforms: TripleBuffer<GlobalUniforms>
	) {
		let renderDesc = MTLRenderPassDescriptor()
//		renderDesc.depthAttachment.clearDepth = 1000000
//		renderDesc.depthAttachment.texture = texture
		renderDesc.colorAttachments[0].texture = texture
		
		let encoder = buffer.makeRenderCommandEncoder(descriptor: renderDesc)!
		
		encoder.setRenderPipelineState(areaHeightMapPipeline)
		encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
		encoder.setVertexBuffer(instanceUniformsBuffer, index: 1)
		encoder.setVertexBuffer(globalUniforms, index: 2)
		
		encoder.setVertexTexture(perlinTexture, index: 0)
		
		var transform = sceneToObjectSpaceTransform
		encoder.setVertexBytes(&transform, length: MemoryLayout<matrix_float4x4>.size, index: 3)
		
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0,
									  instanceCount: instanceCount)
		
		encoder.endEncoding()
	}
	
	func generateChunkUniforms(chunkX: Int, chunkZ: Int) -> TerrainInstanceUniforms {
		var uniforms = TerrainInstanceUniforms()
		uniforms.worldPosition = float2(Float(chunkX), Float(chunkZ)) * chunkSize
		return uniforms
	}

	static func makeRenderPipeline(context: RenderingContext) throws -> MTLRenderPipelineState {
		let lib = context.defaultLibrary
		
		let constantValues = MTLFunctionConstantValues()
		var fc_isGenerateHeightMapPass = false
		constantValues.setConstantValue(&fc_isGenerateHeightMapPass, type: .bool, withName: "fc_isGenerateHeightMapPass")
		
		let desc = MTLRenderPipelineDescriptor()
		desc.vertexFunction = try lib.makeFunction(name: "terrain_vert", constantValues: constantValues)
		desc.fragmentFunction = try lib.makeFunction(name: "terrain_frag", constantValues: constantValues)
		desc.colorAttachments[0].pixelFormat = context.colorPixelFormat
		desc.depthAttachmentPixelFormat = context.depthPixelFormat
		desc.stencilAttachmentPixelFormat = context.stencilPixelFormat
		
		return try context.device.makeRenderPipelineState(descriptor: desc)
	}
	
	static func makeAreaHeightMapPipeline(ctx: RenderingContext) throws -> MTLRenderPipelineState {
		let lib = ctx.defaultLibrary
		
		let constantValues = MTLFunctionConstantValues()
		var fc_isGenerateHeightMapPass = true
		constantValues.setConstantValue(&fc_isGenerateHeightMapPass, type: .bool, withName: "fc_isGenerateHeightMapPass")
		
		let desc = MTLRenderPipelineDescriptor()
		desc.colorAttachments[0].pixelFormat = .r32Float
//		desc.depthAttachmentPixelFormat = .depth32Float
		desc.vertexFunction = try lib.makeFunction(name: "terrain_vert", constantValues: constantValues)
		desc.fragmentFunction = try lib.makeFunction(name: "terrain_height_frag", constantValues: constantValues)
		
		return try ctx.device.makeRenderPipelineState(descriptor: desc)
	}
}
