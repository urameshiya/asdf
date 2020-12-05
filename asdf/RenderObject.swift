//
//  RenderObject.swift
//  asdf
//
//  Created by Chinh Vu on 11/15/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation
import MetalKit

class RenderObject {
	let mesh: MTKMesh
	private var uniforms = Uniforms()
	var physicsBody = PhysicsBody()
	
	init(device: MTLDevice) {
		let model = MDLMesh.newPlane(withDimensions: .init(x: 10, y: 5),
									 segments: .init(x: 1, y: 1),
									 geometryType: .triangles,
									 allocator: MTKMeshBufferAllocator(device: device))
		let mtlDesc = MTLVertexDescriptor.from(formats: [.float3, .float2])
		
		let mdlDesc = MTKModelIOVertexDescriptorFromMetal(mtlDesc)
		guard let attributes = mdlDesc.attributes as? [MDLVertexAttribute] else {
			preconditionFailure()
		}
		attributes[0].name = MDLVertexAttributePosition
		attributes[1].name = MDLVertexAttributeTextureCoordinate
		
		model.vertexDescriptor = mdlDesc
		do {
			mesh = try MTKMesh(mesh: model, device: device)
		} catch {
			preconditionFailure("Cannot build mesh, \(error)")
		}
		let body = physicsBody
		let length: Float = 10
		body.position.x = 3
		body.position.y = 3

		let pendulum = Pendulum()
		physicsBody.addRestoringForce(pendulum)
	}
		
	func prepareForFrame(renderer: Renderer) {
		physicsBody.update()
		uniforms.projectionMatrix = renderer.projectionMatrix
		let modelMatrix = matrix4x4_rotation(radians: 0.0, axis: .init(0, 0, 1))
		let translation = matrix4x4_translation(physicsBody.position.x, physicsBody.position.y, physicsBody.position.z)
		let rotation = matrix4x4_rotation(radians: .pi / 2, axis: .init(1, 0, 0))
		let viewMatrix = renderer.viewMatrix * translation * rotation
		uniforms.modelViewMatrix = simd_mul(viewMatrix, modelMatrix)
	}
	
	func render(in renderPass: MTLRenderCommandEncoder) {
		for (i, buffer) in mesh.vertexBuffers.enumerated() {
			renderPass.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: i)
		}
		renderPass.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
		renderPass.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)

		for submesh in mesh.submeshes {
			renderPass.drawIndexedPrimitives(type: submesh.primitiveType,
											 indexCount: submesh.indexCount,
											 indexType: submesh.indexType,
											 indexBuffer: submesh.indexBuffer.buffer,
											 indexBufferOffset: submesh.indexBuffer.offset)
		}
	}
}
