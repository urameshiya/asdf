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
	var wheels: [WheelData] = [
		.init(posX: -10, posZ: -10, rotY: 0),
		.init(posX: -10, posZ: -10, rotY: 0),
		.init(posX: 10, posZ: 10, rotY: 0),
		.init(posX: 10, posZ: 10, rotY: 0),
	]
	var pos = float3(12, 1, -17)
	var yRot = 0.3 as Float
	var pipeline_hud: MTLRenderPipelineState
	var pipeline_world: MTLRenderPipelineState
	var pipeline_find_max: MTLComputePipelineState
	var pipeline_ground_contact: MTLRenderPipelineState
	var pipeline_contact_depth: MTLDepthStencilState
	var dimX: Float = 0.6
	var dimY: Float = 0.6
	var dimZ: Float = 0.1
	var yOffsetBuffer: TripleBuffer<Float>
	
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
		let rotation = matrix4x4_rotation(radians: -yRot, axis: .init(x: 0, y: 1, z: 0))
		let translation = matrix4x4_translation(-pos.x, -30, -pos.z)
		let remap = matrix_remap_xz(width: dimX, height: dimZ)
		
		return remap * rotation * translation
	}
	
	func render(encoder: MTLRenderCommandEncoder, globalUniforms: TripleBuffer<GlobalUniforms>, camera: Camera) {
		encoder.pushDebugGroup("World car")
		let rotation = matrix4x4_rotation(radians: yRot, axis: .init(0, 1, 0)) * modelTransform()
		var translation = matrix4x4_translation(pos.x, 0, pos.z) * rotation
		encoder.setRenderPipelineState(pipeline_world)
		encoder.setVertexBuffer(vBuffer, index: 0)
		encoder.setVertexBytes(&translation, length: MemoryLayout.size(ofValue: translation), index: 1)
		encoder.setVertexBuffer(globalUniforms, index: 2)
		encoder.setVertexBuffer(yOffsetBuffer, index: 3)
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0)
		encoder.popDebugGroup()

	}
	
	func update(
		commandBuffer: MTLCommandBuffer,
		globalUniforms: TripleBuffer<GlobalUniforms>,
		terrains: ChunkRenderer,
		camera: Camera
	) {
		yOffsetBuffer.currentBufferPointer()[0] = -9999
		yOffsetBuffer.commitBuffer()
		
		do { // make contact map
			let renderpass = MTLRenderPassDescriptor()
			renderpass.colorAttachments[0].texture = wheelTexture
			renderpass.colorAttachments[0].loadAction = .clear
			renderpass.colorAttachments[0].clearColor = MTLClearColorMake(9999, 0, 0, 0)
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
		
		
		let encoder = commandBuffer.makeComputeCommandEncoder()!
		encoder.setComputePipelineState(pipeline_find_max)
		encoder.setTexture(terrainHeightAtWheel, index: 0)
		encoder.setTexture(wheelTexture, index: 1)
		encoder.setBuffer(yOffsetBuffer, index: 0)
		
		let gridsize = MTLSize(width: terrainHeightAtWheel.width / Int(FIND_MAX_SIZE),
							   height: terrainHeightAtWheel.height / Int(FIND_MAX_SIZE),
							   depth: 1)
		let w = pipeline_find_max.threadExecutionWidth
		let tgSize = MTLSize(width: w, height: pipeline_find_max.maxTotalThreadsPerThreadgroup / w, depth: 1)
		encoder.dispatchThreads(gridsize, threadsPerThreadgroup: tgSize)
		
		encoder.endEncoding()
	}
	
	func modelTransform() -> float4x4 {
		return matrix_scale(dimX / 2, dimY / 2, dimZ / 2)
	}
	
	var vBuffer: TypedBuffer<Float>!
	var indexBuffer: TypedBuffer<UInt32>!
	
	func fillWheelMesh(context: RenderingContext) {
		let center = float2(x: 0, y: 0)
		let r: Float = 1
		var vertices: [Float] = [center.x, center.y, -1, center.x, center.y, 1]
		
		var faces: [UInt32] = []
		
		let segments = 50
		var lastVertexOnCircle = 0
		var currentVertex = 2
		for i in 0..<segments {
			let theta = 2 * Float.pi / Float(segments) * Float(i)
			let x = center.x + r * sin(theta)
			let y = center.y + r * cos(theta)
			vertices.append(contentsOf: [x, y, -1])
			vertices.append(contentsOf: [x, y, 1])
			
			lastVertexOnCircle = currentVertex
			if i == segments - 1 {
				currentVertex = 2
			} else {
				currentVertex += 2
			}

			faces.append(contentsOf: triangleFace((0, lastVertexOnCircle, currentVertex)))
			faces.append(contentsOf: triangleFace((1, lastVertexOnCircle + 1, currentVertex + 1)))
			faces.append(contentsOf: quadFace((lastVertexOnCircle, lastVertexOnCircle + 1, currentVertex, currentVertex + 1)))
		}
		
		vBuffer = .init(count: vertices.count, allocator: { (size) -> MTLBuffer in
			context.device.makeBuffer(length: size, options: [.storageModeShared])!
		})
		
		indexBuffer = .init(count: faces.count, allocator: { (size) -> MTLBuffer in
			context.device.makeBuffer(length: size, options: [.storageModeShared])!
		})
		
		vBuffer.fill(with: vertices)
		indexBuffer.fill(with: faces)
	}
	
	private func triangleFace(_ face: (Int, Int, Int)) -> [UInt32] {
		return [face.0, face.1, face.2].map(UInt32.init)
	}
	
	private func quadFace(_ face: (Int, Int, Int, Int)) -> [UInt32] {
		return [face.0, face.1, face.2, face.1, face.2, face.3].map(UInt32.init)
	}
	
	var wheelAxis = float3(0, 0, 1) {
		didSet {
			wheelAxis = normalize(wheelAxis)
		}
	} // normalized
	
	func handleTerrains(terrains: Terrains) {
		let nearbyTriangles = terrains.getTriangles(overlapping: .init(x: pos.x - dimX / 2, y: pos.z - dimZ / 2, width: dimX, height: dimZ))
		let wheelRadius = dimX / 2
		let wheelAxis = float3(0, 0, 1)
		
		let simplex = GJKSimplex()
		let direction = Vector3(1, 0, 0)
		for triangle in nearbyTriangles {
			if gjk_checkCollision(triangle) {
				print("collision")
			}
		}
	}
	
	func gjk_supportFunction(axis: Vector3) -> Vector3 {
		let r = dimY / 2
		let halfHeight = dimZ / 2
		let dp = dot(axis, wheelAxis)
		let unitRadial = normalize(axis - wheelAxis * dp)
		let vWheelAxis = halfHeight * sign(dp) * wheelAxis
		let vRadial = r * unitRadial
		return pos + vWheelAxis + vRadial
	}
	
	func gjk_checkCollision(_ shape: Triangle) -> Bool {
		var axis = Vector3(1, 0, 0)
		let simplex = GJKSimplex()
		var minkowski = self.gjk_supportFunction(axis: axis) - shape.gjk_supportFunction(axis: -axis)
		simplex.addPoint(minkowski)
		
		while true {
			axis = simplex.axisTowardsOrigin()
			minkowski = self.gjk_supportFunction(axis: axis) - shape.gjk_supportFunction(axis: -axis)
			if dot(minkowski, axis) < 0 { // the entire Minkowski diff lies away from origin
				return false
			}
			simplex.addPoint(minkowski)
			if simplex.containsOrigin {
				return true
			}
		}
	}
	
	func projectedPoints(onto normalAxis: Vector3) -> [Float] {
		let dp = dot(normalAxis, wheelAxis)
		let normalToFaceAngle = asin(dp)
		let diameter = dimY
		let length = dimZ
		let v0 = diameter * cos(normalToFaceAngle)
		let v1 = length * sin(normalToFaceAngle)
		
		// project vertices of rectangular cross-section onto normalAxis
		return [
			0,
			v0,
			v1,
			v1 + v0 // a + b = c => a (dot) u + b.u = c.u
		]
	}
	
	func zeroPoint(axis: Vector3) -> Vector3 {
		let cylinderLength = dimZ
		let radius = dimY / 2
		let center = pos - wheelAxis * cylinderLength
		let crossSectionNormal = normalize(cross(wheelAxis, axis))
		return center + cross(wheelAxis, crossSectionNormal) * radius
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

class WheelData {
	var posX: Float
	var posZ: Float
	var rotY: Float
	
	init(posX: Float, posZ: Float, rotY: Float) {
		self.posX = posX
		self.posZ = posZ
		self.rotY = rotY
	}
}

class GJKSimplex {
	var containsOrigin = false
	var points = [Vector3]() {
		didSet {
			assert(points.count <= 4, "Simplex must be at most 3 simplex")
		}
	}
	
	func addPoint(_ p: Vector3) {
		points.append(p)
		
		if points.count == 4 {
			containsOrigin = isOriginOnSameSide(base: (points[0], points[1], points[2]), p: points[3])
				&& isOriginOnSameSide(base: (points[1], points[2], points[3]), p: points[0])
				&& isOriginOnSameSide(base: (points[2], points[3], points[0]), p: points[1])
				&& isOriginOnSameSide(base: (points[0], points[1], points[3]), p: points[2])
			points.remove(at: 0)
		}
	}
	
	private func isOriginOnSameSide(base: (Vector3, Vector3, Vector3), p: Vector3) -> Bool {
		let normal = cross(base.1 - base.0, base.2 - base.0)
		let dP = dot(p - base.0, normal)
		let dOrigin = dot(-base.0, normal)
		return dOrigin == 0 // origin is coplanar with base
			|| sign(dOrigin) == sign(dP)
	}
	
	func axisTowardsOrigin() -> Vector3 {
		var axis = Vector3.zero
		switch points.count {
		case 1:
			axis = -points[0]
		case 2:
			let a = points[1] - points[0]
			let b = -points[0]
			axis = b * dot(a, a) - a * dot(a, b) // a x (b x c)
		case 3:
			let a = points[1] - points[0]
			let b = points[2] - points[0]
			let normal = cross(a, b)
			let AO = -points[0]
			axis = dot(AO, axis) < 0 ? -normal : normal
		default:
			assertionFailure()
		}
		
		return normalize(axis)
	}
}

struct Rect {
	var x, y: Float
	var width, height: Float
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
