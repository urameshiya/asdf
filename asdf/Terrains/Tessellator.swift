//
//  Tessellator.swift
//  asdf
//
//  Created by Chinh Vu on 12/10/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

class TriangleTessellator {
	typealias UMBPtr<Type> = UnsafeMutableBufferPointer<Type>
	let levelCount: Int
	let edgeVCount: Int
	let vTotal: Int
	let patchCount: Int
	
	init(levelCount: Int) {
		assert(levelCount > 0)
		self.levelCount = levelCount
		edgeVCount = levelCount + 1
		vTotal = (edgeVCount) * (edgeVCount + 1) / 2
		patchCount = levelCount * levelCount // 1 + 3 + 5 + ...
	}
	
	private func makeBuffer() -> (vertices: [Float], patches: [Int], barys: [UInt8]) {
		var patches: [Int]!
		var barys: [UInt8]!
		let vertices = [Float].init(unsafeUninitializedCapacity: vTotal * 3) { (vPtr, vCount) in
			patches = .init(unsafeUninitializedCapacity: patchCount * 3) { (pPtr, patchCount) in
				barys = .init(unsafeUninitializedCapacity: vTotal) { bPtr, bCount in
					tessellateBary(vertices: vPtr, patches: pPtr, barys: bPtr)
					bCount = vTotal
				}
				patchCount = self.patchCount * 3
			}
			vCount = vTotal * 3
		}
		
		return (vertices, patches, barys)
	}
		
	func tessellate(
		vertices: [Float], indices: [UInt32],
		outPositions: AnyMutablePointer<packed_float3>,
		outIndices: AnyMutablePointer<UInt32>,
		outBarys: AnyMutablePointer<UInt8>
	) {
		let (baryVerts, baryIndices, baryCoords) = makeBuffer()
		
		assert(indices.count % 3 == 0)
		
		let vCount = baryVerts.count / 3
		
		let outPositions = AppendSemantics(pointer: outPositions)
		let outIndices = AppendSemantics(pointer: outIndices)
		let outBarys = AppendSemantics(pointer: outBarys)
		for patch in 0..<indices.count / 3 {
			let patchIndex = patch * 3 // every 3 indices make a triangle
			let i0 = indices[patchIndex]
			let i1 = indices[patchIndex + 1]
			let i2 = indices[patchIndex + 2]
			let v0 = getVertex(at: i0, vertices: vertices)
			let v1 = getVertex(at: i1, vertices: vertices)
			let v2 = getVertex(at: i2, vertices: vertices)
			
			for i in stride(from: 0, to: baryVerts.count, by: 3) {
				let vv0 = v0 * baryVerts[i]
				let vv1 = v1 * baryVerts[i + 1]
				let vv2 = v2 * baryVerts[i + 2]
				let vv = vv0 + vv1 + vv2
				
				outPositions.append(.init(x: vv.x, y: vv.y, z: vv.z))
			}
			outBarys.append(contentsOf: baryCoords)
			outIndices.append(contentsOf: baryIndices.map { UInt32($0 + patch * vCount) }) // new vertices come after old ones
		}
		
	}
		
	private func getVertex(at index: UInt32, vertices: [Float]) -> SIMD3<Float> {
		let start = Int(index * 3)
		return .init(vertices[start], vertices[start + 1], vertices[start + 2])
	}
					
	private func tessellateBary(vertices: UMBPtr<Float>, patches: UMBPtr<Int>, barys: UMBPtr<UInt8>) {
		var vOffset = 3
		
		vertices[0] = 1
		vertices[1] = 0
		vertices[2] = 0
		
		var bOffset = 1
		barys[0] = 0
		for level in 1...levelCount {
			// u is the unchanged area ratio between points within the same level
			let u = Float(levelCount - level) / Float(levelCount)
			
			var bary = UInt8(level % 3)
			for point in 0...level {
				let sumVW = 1 - u
				let v = sumVW * Float(point) / Float(level)

				assert(u + v <= 1)
				
				vertices[vOffset] = u
				vertices[vOffset + 1] = v
				vertices[vOffset + 2] = sumVW - v
				
				barys[bOffset] = bary
				
				bOffset += 1
				bary = (bary + 1) % 3
				vOffset += 3
			}
		}
		
		var p = 0
		var downTri = SIMD3<Int>(0, 1, 2)
		var upTri = SIMD3<Int>(0, 2, 1) // chosen so that after first iteration upTri = (1, 4, 2)
		for level in 0..<levelCount {
			for horOffset in 0..<level {
				let down = downTri &+ horOffset // shift triangle to the right
				let up = upTri &+ horOffset
				patches.set(start: p, down.x, down.y, down.z)
				patches.set(start: p + 3, up.x, up.y, up.z)
				p += 6
			}
			let down = downTri &+ level
			patches.set(start: p, down.x, down.y, down.z)
			p += 3
			downTri &+= .init(level + 1, level + 2, level + 2)
			upTri &+= .init(level + 1, level + 2, level + 1)
		}
	}
}

private class AppendSemantics<Element> {
	private(set) var count = 0
	let pointer: AnyMutablePointer<Element>
	
	init(pointer: AnyMutablePointer<Element>) {
		self.pointer = pointer
	}
	
	func append(_ element: Element) {
		assert(count < pointer.count)
		pointer[count] = element
		count += 1
	}
	
	func append<S>(contentsOf sequence: S) where S: Sequence, S.Element == Element {
		sequence.forEach { self.append($0) }
	}
}

extension UnsafeMutableBufferPointer {
	fileprivate func set(start offset: Int, _ elements: Element...) {
		elements.enumerated().forEach { (i, element) in
			self[offset + i] = element
		}
	}
}
