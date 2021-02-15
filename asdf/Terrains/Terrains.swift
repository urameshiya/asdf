//
//  Terrains.swift
//  asdf
//
//  Created by Chinh Vu on 1/16/21.
//  Copyright © 2021 urameshiyaa. All rights reserved.
//

import Foundation

class Terrains {
	private var tiles = [TilePoint: Tile]()
	
}

class Tile: Hashable {
	var tilePos: TilePoint
	var triangles: [Triangle]
	
	init(tilePos: TilePoint, triangles: [Triangle]) {
		self.tilePos = tilePos
		self.triangles = triangles
	}
	
	static func == (lhs: Tile, rhs: Tile) -> Bool {
		return lhs.tilePos == rhs.tilePos
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(tilePos)
	}
}

protocol Triangle {
	var v0: Vector3 { get }
	var v1: Vector3 { get }
	var v2: Vector3 { get }
	func gjk_supportFunction(axis: Vector3) -> Vector3
	func setCollided(_ collided: Bool)
}

class TriangleMemoryView: Triangle {
	private var buffer: UnsafeMutableBufferPointer<TerrainVertexIn>
	let offset: (Int, Int, Int)
	
	init(buffer: TypedBuffer<TerrainVertexIn>, offset: (Int, Int, Int)) {
		self.buffer = buffer.bufferPointer()
		self.offset = offset
	}
	
	var v0: Vector3 {
		return Vector3(buffer[offset.0].position)
	}
	
	var v1: Vector3 {
		return Vector3(buffer[offset.1].position)
	}
	
	var v2: Vector3 {
		return Vector3(buffer[offset.2].position)
	}
	
	func setCollided(_ collided: Bool) {
		buffer[offset.0].collided = collided
		buffer[offset.1].collided = collided
		buffer[offset.2].collided = collided
	}
	
	func gjk_supportFunction(axis: Vector3) -> Vector3 {
		return [v0, v1, v2].max { dot($0, axis) < dot($1, axis) }!
	}
}

struct TriangleStruct: Triangle {
	var v0, v1, v2: Vector3
	var normal: Vector3 {
		return normalize(cross(v1 - v0, v2 - v0))
	}
	
	init(v0: Vector3, v1: Vector3, v2: Vector3) {
		self.v0 = v0
		self.v1 = v1
		self.v2 = v2
	}
	
	init(v0: packed_float3, v1: packed_float3, v2: packed_float3) {
		self.init(v0: Vector3(v0), v1: Vector3(v1), v2: Vector3(v2))
	}
	
	func gjk_supportFunction(axis: Vector3) -> Vector3 {
		return [v0, v1, v2].max { dot($0, axis) < dot($1, axis) }!
	}
	
	func setCollided(_ collided: Bool) {
		// NO-OP
	}
}

extension Vector3 {
	init(_ v: packed_float3) {
		self.init(v.x, v.y, v.z)
	}
}

struct Point3D {
	var x, y, z: Float
}

struct TilePoint: Equatable, Hashable {
	var u: Int
	var v: Int
}
