//
//  Metal.swift
//  asdf
//
//  Created by Chinh Vu on 11/18/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation
import MetalKit

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
