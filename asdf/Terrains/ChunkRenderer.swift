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
	let baseVertices: TypedBuffer<TerrainVertexIn>
	let indexBuffer: TypedBuffer<UInt32>
	var instanceUniformsBuffer: TripleBuffer<TerrainInstanceUniforms>
	let renderPipeline: MTLRenderPipelineState
	let perlinTexture: MTLTexture
	let instanceCount: Int
	
	init?(context: RenderingContext) {
		let device = context.device
		
		do {
			renderPipeline = try ChunkRenderer.makeRenderPipeline(context: context)
			ppl_computeTerrain = try device.makeComputePipelineState(function: context.defaultLibrary.makeFunction(name: "populate_terrain")!)
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
		
		baseVertices = TypedBuffer(count: tessellator.vTotal * 2) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		indexBuffer = TypedBuffer(count: tessellator.patchCount * 3 * 2) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		tessellator.tessellate(vertices: preVerts,
							   indices: preIndices,
							   outPositions: .init(baseVertices.bufferPointer().accessing(\.position)),
							   outIndices: .init(indexBuffer.bufferPointer()),
							   outBarys: .init(baseVertices.bufferPointer().accessing(\.bary)))
		
		let side = renderDistance * 2 + 1
		instanceCount = side * side
		
		instanceUniformsBuffer = TripleBuffer(count: instanceCount) { length in
			device.makeBuffer(length: length, options: [.storageModeShared])!
		}
		
		populatedVertexBuffer = TypedBuffer(count: instanceCount * baseVertices.elementCount) { length in
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
	func update(camera: Camera, computeEncoder: MTLComputeCommandEncoder) -> MTLCommandBufferHandler {
		let chunkX = Int(floor(camera.x / chunkSize))
		let chunkZ = Int(floor(camera.z / chunkSize))
		
		if (chunkX, chunkZ) == renderCenter {
			return { _ in }
		}
		isTerrainPopulated = false
		
		let uniforms = instanceUniformsBuffer.currentBufferPointer()
		
		var instanceId = 0
		for z in -renderDistance...renderDistance {
			for x in -renderDistance...renderDistance {
				uniforms[instanceId] = generateChunkUniforms(chunkX: chunkX + x,
															 chunkZ: chunkZ + z,
															 bufferOffset: instanceId * baseVertices.elementCount)
				instanceId += 1
			}
		}
		assert(instanceId == instanceCount)
		
		instanceUniformsBuffer.commitBuffer()
		
		renderCenter = (chunkX, chunkZ)
		
		computeTerrain(encoder: computeEncoder)
		
		return { _ in self.isTerrainPopulated = true }
	}
	
	func render(encoder: MTLRenderCommandEncoder, globalUniforms: TripleBuffer<GlobalUniforms>) {
		encoder.setRenderPipelineState(renderPipeline)
		encoder.setVertexBuffer(populatedVertexBuffer, offset: 0, index: 0)
		encoder.setVertexBuffer(globalUniforms, index: 1)
		var perInstanceVCount = UInt32(tessellator.vTotal)
		encoder.setVertexBytes(&perInstanceVCount, length: MemoryLayout.size(ofValue: perInstanceVCount), index: 2)
		
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0,
									  instanceCount: instanceCount)
	}
	
	var ppl_computeTerrain: MTLComputePipelineState
	var populatedVertexBuffer: TypedBuffer<TerrainVertexIn>
	var isTerrainPopulated = false
	
	func computeTerrain(encoder: MTLComputeCommandEncoder) {
		encoder.setComputePipelineState(ppl_computeTerrain)
		encoder.setBuffer(baseVertices, index: 0)
		encoder.setTexture(perlinTexture, index: 0)
		encoder.setBuffer(instanceUniformsBuffer, index: 1)
		encoder.setBuffer(populatedVertexBuffer, index: 2)
		
		let w = ppl_computeTerrain.threadExecutionWidth
		let tgSize = MTLSize(width: w, height: ppl_computeTerrain.maxTotalThreadsPerThreadgroup / w, depth: 1)
		let gridSize = MTLSize(width: baseVertices.elementCount, height: instanceCount, depth: 1)
		encoder.dispatchThreads(gridSize, threadsPerThreadgroup: tgSize)
	}
	
	func generateChunkUniforms(chunkX: Int, chunkZ: Int, bufferOffset: Int) -> TerrainInstanceUniforms {
		var uniforms = TerrainInstanceUniforms()
		uniforms.worldPosition = float2(Float(chunkX), Float(chunkZ)) * chunkSize
		uniforms.chunkOffset = UInt32(bufferOffset)
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
	
	func getBufferOffsetForChunk(u: Int, v: Int) -> Int? {
		let x = u - renderCenter.x + renderDistance
		let y = v - renderCenter.z + renderDistance
		
		let offset = y * (2 * renderDistance + 1) + x
		return 0..<instanceCount ~= offset ? offset * baseVertices.elementCount : nil
	}
	
	func getTriangles(overlapping rect: Rect) -> [Triangle] {
		var result = [Triangle]()
		let uStart = Int(floor(rect.x / chunkSize))
		let vStart = Int(floor(rect.y / chunkSize))
		let uEnd = Int(ceil((rect.x + rect.width) / chunkSize))
		let vEnd = Int(ceil((rect.y + rect.height) / chunkSize))
		
		let vPtr = populatedVertexBuffer.bufferPointer()
		for u in uStart...uEnd {
			for v in vStart...vEnd {
				guard let chunkVOffset = getBufferOffsetForChunk(u: u, v: v) else { continue }
				let indices = indexBuffer.bufferPointer()
				for i in stride(from: indices.startIndex, to: indices.endIndex, by: 3) {
//					result.append(.init(v0: vPtr[chunkVOffset + Int(indices[i])].position,
//										v1: vPtr[chunkVOffset + Int(indices[i + 1])].position,
//										v2: vPtr[chunkVOffset + Int(indices[i + 2])].position))
					result.append(TriangleMemoryView(buffer: populatedVertexBuffer,
													 offset: (chunkVOffset + Int(indices[i]),
															  chunkVOffset + Int(indices[i + 1]),
															  chunkVOffset + Int(indices[i + 2]))))
				}
			}
		}
		
		return result
	}
}
