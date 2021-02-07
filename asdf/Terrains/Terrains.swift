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
	var tileSize: Float = 10
	
	init() {
		
	}
	
	func getTriangles(overlapping rect: Rect) -> [Triangle] {
		var result = [Triangle]()
		let uStart = Int(rect.x / tileSize)
		let vStart = Int(rect.y / tileSize)
		let uEnd = Int((rect.x + rect.width) / tileSize)
		let vEnd = Int((rect.y + rect.height) / tileSize)
		
		for u in uStart...uEnd {
			for v in vStart...vEnd {
				if let tile = tiles[.init(u: u, v: v)] {
					result.append(contentsOf: tile.triangles)
				}
			}
		}
		
		return result
	}
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

struct Triangle {
	var v0, v1, v2: Vector3
	var normal: Vector3 {
		return normalize(cross(v1 - v0, v2 - v0))
	}
	
	init(v0: Vector3, v1: Vector3, v2: Vector3) {
		self.v0 = v0
		self.v1 = v1
		self.v2 = v2
	}
	
	func gjk_supportFunction(axis: Vector3) -> Vector3 {
		return [v0, v1, v2].max { dot($0, axis) < dot($1, axis) }!
	}
}

struct Point3D {
	var x, y, z: Float
}

struct TilePoint: Equatable, Hashable {
	var u: Int
	var v: Int
}
