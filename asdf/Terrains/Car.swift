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
	var yRot = 0.0 as Float
	var pipeline_hud: MTLRenderPipelineState
	var pipeline_world: MTLRenderPipelineState
	var pipeline_find_max: MTLComputePipelineState
	var pipeline_ground_contact: MTLRenderPipelineState
	var pipeline_contact_depth: MTLDepthStencilState
	var dimX: Float = 30
	var dimY: Float = 30
	var dimZ: Float = 10
	var yOffsetBuffer: TripleBuffer<Float>
	var isInCollision: Bool = false
	
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
		var translation = matrix4x4_translation(pos.x, pos.y, pos.z) * rotation
		encoder.setRenderPipelineState(pipeline_world)
		encoder.setVertexBuffer(vBuffer, index: 0)
		encoder.setVertexBytes(&translation, length: MemoryLayout.size(ofValue: translation), index: 1)
		encoder.setVertexBuffer(globalUniforms, index: 2)
		encoder.setVertexBuffer(yOffsetBuffer, index: 3)
		encoder.setFragmentBytes(&isInCollision, length: MemoryLayout<Bool>.size, index: 0)
		encoder.drawIndexedPrimitives(type: .triangle,
									  indexCount: indexBuffer.elementCount,
									  indexType: .uint32,
									  indexBuffer: indexBuffer.buffer,
									  indexBufferOffset: 0)
		encoder.popDebugGroup()

	}
	
	func update(
		computeEncoder: MTLComputeCommandEncoder,
		globalUniforms: TripleBuffer<GlobalUniforms>,
		terrains: ChunkRenderer,
		camera: Camera
	) {
		handleTerrains(terrains)
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
	
	func handleTerrains(_ terrains: ChunkRenderer) {
		if !terrains.isTerrainPopulated || !gjk_shouldInvalidate {
			return
		}
		gjk_shouldInvalidate = false
		
		let nearbyTriangles = terrains.getTriangles(overlapping: .init(x: pos.x - dimX / 2, y: pos.z - dimZ / 2, width: dimX, height: dimZ))
		
		isInCollision = false
		for triangle in nearbyTriangles {
			if gjk_checkCollision(triangle) {
				isInCollision = true
				return
			}
		}
	}
	
	func gjk_supportFunction(axis: Vector3) -> Vector3 {
		let r = dimY / 2
		let halfHeight = dimZ / 2
		let dp = dot(axis, wheelAxis)
		let unitRadial = normalize(axis - wheelAxis * dp)
		let vWheelAxis = halfHeight * sign(dp) * wheelAxis
		if unitRadial.x.isNaN { // avoids division by zero in unitRadial
			return pos + vWheelAxis
		}
		let vRadial = r * unitRadial
		return pos + vWheelAxis + vRadial
	}
	
	private var gjk_lastSimplex: GJKSimplex?
	var gjk_shouldInvalidate = true
	
	func gjk_checkCollision(_ shape: Triangle) -> Bool {
		var axis = Vector3(1, 0, 0)
		let simplex = GJKSimplex()
		var minkowski = self.gjk_supportFunction(axis: axis) - shape.gjk_supportFunction(axis: -axis)
		simplex.addPoint(minkowski)
		
		gjk_lastSimplex = simplex
		
		while true {
			axis = simplex.axisTowardsOrigin()
			minkowski = self.gjk_supportFunction(axis: axis) - shape.gjk_supportFunction(axis: -axis)
			if dot(minkowski, axis) < 0 { // the entire Minkowski diff lies away from origin
				return false
			}
			simplex.addPoint(minkowski)
			if simplex.containsOrigin {
				print(shape)
				shape.setCollided(true)
				return true
			}
		}
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
	private var axis: Vector3 = .zero
	
	func addPoint(_ p: Vector3) {
		points.append(p)
		
		switch points.count {
		case 1:
			axis = -points[0]
		case 2:
			let a = points[1] - points[0]
			let b = -points[0]
			axis = b * dot(a, a) - a * dot(a, b) // a x (b x a)
			assert(dot(axis, b) >= 0)
		case 3:
			let a = points[1] - points[0]
			let b = points[2] - points[0]
			let normal = cross(a, b)
			let AO = -points[0]
			axis = dot(AO, normal) < 0 ? -normal : normal
			assert(dot(axis, AO) >= 0)
		case 4:
			containsOrigin = checkOriginIsInSameRegion(baseIndices: (0, 1, 2), p: 3)
				&& 	checkOriginIsInSameRegion(baseIndices: (1, 2, 3), p: 0)
				&& 	checkOriginIsInSameRegion(baseIndices: (2, 3, 0), p: 1)
				&& 	checkOriginIsInSameRegion(baseIndices: (0, 1, 3), p: 2)
		default:
			assertionFailure()
			break
		}
		
		axis = normalize(axis)
	}
	
	private func checkOriginIsInSameRegion(baseIndices: (Int, Int, Int), p: Int) -> Bool {
		let base = (points[baseIndices.0], points[baseIndices.1], points[baseIndices.2])
		let normal = cross(base.1 - base.0, base.2 - base.0)
		let dP = dot(points[p] - base.0, normal)
		let dOrigin = dot(-base.0, normal)
		if dOrigin == 0 || sign(dOrigin) == sign(dP) {
			return true
		} else {
			axis = normal * sign(dOrigin)
			points.remove(at: p)
			assert(dot(axis, -base.0) >= 0)
			return false
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
		return axis
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
