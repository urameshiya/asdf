//
//  PerlinNoise2D.swift
//  asdf
//
//  Created by Chinh Vu on 12/14/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

class PerlinNoise2D {
	var gradients: [SIMD2<Float>]
	private let gridSize = 256 // power of two
	private var gridMask: Int { gridSize - 1 }
	private let permutationTable: [Int]
	
	init() {
		let vCount = gridSize
		gradients = .init(unsafeUninitializedCapacity: vCount) { [vCount] buffer, initCount in
			for i in 0..<vCount {
				buffer[i] = .random(in: -1...1)
				buffer[i] = normalize(buffer[i])
			}
			initCount = vCount
		}
		permutationTable = .init([0..<gridSize, 0..<gridSize].flatMap { $0 })
	}
	
	func at(_ coord: SIMD2<Float>) -> Float {
		let bucket = floor(coord)
		let x0 = Int(bucket.x) & gridMask
		let y0 = Int(bucket.y) & gridMask
		let normCoord = coord - bucket
		assert(-1...1 ~= normCoord.x && -1...1 ~= normCoord.y)
		
		func vertexWeight(_ x: Int, _ y: Int) -> Float {
			assert(0..<256 ~= x && 0..<256 ~= y)
			let vDistance = normCoord - .init(Float(x), Float(y))
			assert(-1...1 ~= vDistance.x && -1...1 ~= vDistance.y)
			let gradient = gradients[hashFunc(x: x0 + x, y: y0 + y)]
			return dot(vDistance, gradient)
		}
		
		func hashFunc(x: Int, y: Int) -> Int {
			return permutationTable[x + permutationTable[y]]
		}
		
		let w00 = vertexWeight(0, 0)
		let w01 = vertexWeight(0, 1)
		let w10 = vertexWeight(1, 0)
		let w11 = vertexWeight(1, 1)
		
		let t = smoothstep(normCoord, edge0: .zero, edge1: .one)
		
		let x0lerp = simd_mix(w00, w10, t.x)
		let x1lerp = simd_mix(w01, w11, t.x)
		return simd_mix(x0lerp, x1lerp, t.y)
	}
}
