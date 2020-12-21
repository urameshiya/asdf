//
//  Metal.swift
//  asdf
//
//  Created by Chinh Vu on 11/18/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation
import MetalKit

struct RenderingContext {
	let device: MTLDevice
	let commandQueue: MTLCommandQueue
	let defaultLibrary: MTLLibrary
	let colorPixelFormat: MTLPixelFormat
	let depthPixelFormat: MTLPixelFormat
	let stencilPixelFormat: MTLPixelFormat
}

class TypedBuffer<Element> {
	let buffer: MTLBuffer
	let elementCount: Int

	init(count: Int, allocator: (Int) throws -> MTLBuffer) rethrows {
		let totalBufferSize = count * MemoryLayout<Element>.size
		buffer = try allocator(totalBufferSize)
		elementCount = count
	}
	
	func bufferPointer() -> UnsafeMutableBufferPointer<Element> {
		return .init(start: (buffer.contents()).bindMemory(to: Element.self, capacity: elementCount),
					 count: elementCount)
	}
}

class TripleBuffer<Element> {
	private var renderingBufferIndex: Int = 0
	fileprivate let buffer: MTLBuffer
	fileprivate let perBufferElementCount: Int
	var renderingBufferOffset: Int {
		return renderingBufferIndex * perBufferSize
	}
	
	init(count: Int, allocator: (Int) throws -> MTLBuffer) rethrows {
		let totalBufferSize = count * MemoryLayout<Element>.size * 3
		buffer = try allocator(totalBufferSize)
		perBufferElementCount = count
	}
	
	private var perBufferSize: Int {
		return perBufferElementCount * MemoryLayout<Element>.size
	}
	
	func currentBufferPointer() -> UnsafeMutableBufferPointer<Element> {
		let nextBufferIndex = (renderingBufferIndex + 1) % 3
		return .init(start: (buffer.contents() + nextBufferIndex * perBufferSize).bindMemory(to: Element.self, capacity: perBufferElementCount),
					 count: perBufferElementCount)
	}
	
	func commitBuffer() {
		renderingBufferIndex = (renderingBufferIndex + 1) % 3
	}
}

extension MTLRenderCommandEncoder {
	func setVertexBuffer<E>(_ buffer: TripleBuffer<E>, index: Int) {
		setVertexBuffer(buffer.buffer, offset: buffer.renderingBufferOffset, index: index)
	}
	
	func setVertexBuffer<E>(_ buffer: TypedBuffer<E>, offset: Int, index: Int) {
		setVertexBuffer(buffer.buffer, offset: offset * MemoryLayout<E>.stride, index: index)
	}
}

extension MTLBlitCommandEncoder {
	func copy<Element>(from src: TypedBuffer<Element>, to dest: MTLTexture) {
		assert(src.elementCount == dest.width * dest.height)
		copy(from: src.buffer,
			 sourceOffset: 0,
			 sourceBytesPerRow: dest.width * MemoryLayout<Element>.size,
			 sourceBytesPerImage: src.elementCount * MemoryLayout<Element>.size,
			 sourceSize: .init(width: dest.width, height: dest.height, depth: 1),
			 to: dest,
			 destinationSlice: 0,
			 destinationLevel: 0,
			 destinationOrigin: .init())
	}
}

extension MTLVertexAttributeDescriptor {
	func format(_ format: MTLVertexFormat) -> Self {
		self.format = format
		return self
	}
	
	func offset(_ offset: Int) -> Self {
		self.offset = offset
		return self
	}
	
	func bufferIndex(_ index: Int) -> Self {
		self.bufferIndex = index
		return self
	}
	
}

extension MTLVertexBufferLayoutDescriptor {
	func stride(_ stride: Int) -> Self {
		self.stride = stride
		return self
	}
	
	func stepRate(_ stepRate: Int) -> Self {
		self.stepRate = stepRate
		return self
	}
	
	func stepFunction(_ stepFunction: MTLVertexStepFunction) -> Self {
		self.stepFunction = stepFunction
		return self
	}
}

protocol VertexAttributes: CaseIterable {
	var format: MTLVertexFormat { get }
}

extension MTLVertexDescriptor {
	static func from(formats: [MTLVertexFormat]) -> MTLVertexDescriptor {
		let desc = MTLVertexDescriptor()
		for (i, format) in formats.enumerated() {
			_ = desc.attributes[i].format(format).offset(0).bufferIndex(i)
			_ = desc.layouts[i].stride(format.size).stepFunction(.perVertex).stepRate(1)
		}
		return desc
	}
	
	static func from<Enum>(_ enumeration: Enum.Type) -> MTLVertexDescriptor where Enum: VertexAttributes {
		return from(formats: enumeration.allCases.map {$0.format})
	}
}

extension MTLVertexFormat {
	var size: Int {
		return vectorSize * elementSize
	}
	
	private var elementSize: Int {
		switch self {
		case .char, .char2, .char3, .char4:
			return 1
		case .float, .float2, .float3, .float4, .int, .int2, .int3, .int4:
			return 4
		default:
			fatalError("Not implemented")
		}
	}
	
	private var vectorSize: Int {
		switch self {
		case .char, .float, .int:
			return 1
		case .char2, .float2, .int2:
			return 2
		case .char3, .float3, .int3:
			return 3
		default:
			fatalError("Not implemented")
		}
	}
}
