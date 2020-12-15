//
//  TerrainGenerator.swift
//  asdf
//
//  Created by Chinh Vu on 12/7/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import AppKit
import MetalKit

class TerrainGenerator {	
	let noise = PerlinNoise2D()
	let vertexBuffer: MTLBuffer
	let indexBuffer: MTLBuffer
	let resolution = 10
	let tessellator: TriangleTessellator
	let vCount: Int
	let indexCount: Int
	let pipeline:  MTLRenderPipelineState
	
	init(device: MTLDevice, mtkView: MTKView) {
		tessellator = .init(levelCount: resolution)
		pipeline = try! TerrainGenerator.createPipeline(device: device, mtkView: mtkView)
		
		let minX: Float = 0
		let maxX: Float = 100
		let minZ: Float = 0
		let maxZ: Float = 100
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
		var (verts, indices) = tessellator.tessellate(vertices: preVerts, indices: preIndices)
		
		assert(verts.count % 3 == 0)
		assert(indices.count % 3 == 0)
		
		vCount = verts.count / 3
		indexCount = indices.count
		
		// apply height map
		var p = 0
		for _ in 0..<vCount {
			let x = verts[p]
			let z = verts[p + 2]
			verts[p + 1] = noise.at(.init(x: x / 37, y: z / 37)) * 20
			p += 3
		}

			
		vertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<Float>.size, options: [.storageModeShared])!
		indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt32>.size, options: [.storageModeShared])!
	}
		
	func render(encoder: MTLRenderCommandEncoder) {
		encoder.setRenderPipelineState(pipeline)
		encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
		
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer,
									  indexBufferOffset: 0)
	}
	
	static func createPipeline(device: MTLDevice, mtkView: MTKView) throws -> MTLRenderPipelineState {
		let lib = device.makeDefaultLibrary()!
		
		let desc = MTLRenderPipelineDescriptor()
		desc.vertexFunction = lib.makeFunction(name: "tess_vertex")!
		desc.fragmentFunction = lib.makeFunction(name: "tess_frag")!
		desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
		desc.depthAttachmentPixelFormat = mtkView.depthStencilPixelFormat
		desc.stencilAttachmentPixelFormat = mtkView.depthStencilPixelFormat
		
		return try device.makeRenderPipelineState(descriptor: desc)
	}
}
