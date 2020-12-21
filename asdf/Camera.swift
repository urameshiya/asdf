//
//  Camera.swift
//  asdf
//
//  Created by Chinh Vu on 12/14/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

class Camera {
	var x: Float = 0 { didSet { uniformsNeedUpdate = true } }
	var y: Float = 4 { didSet { uniformsNeedUpdate = true } }
	var z: Float = 0 { didSet { uniformsNeedUpdate = true } }
	private(set) var fovyRadians: Float = 0
	private(set) var aspectRatio: Float = 0
	private(set) var nearZ: Float = 0
	private(set) var farZ: Float = 0
	private var _uniforms = CameraUniforms()
	var uniforms: CameraUniforms {
		if uniformsNeedUpdate {
			updateUniforms()
		}
		return _uniforms
	}
	var scrollspeed: Float = 10 // per second
	var autoScrollMask: CameraAutoScrollMask = []
	private var uniformsNeedUpdate = true
	
	func updateProjectionMatrix(fovyRadians: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {
		_uniforms.projectionMatrix = matrix_perspective_right_hand(fovyRadians: fovyRadians, aspectRatio: aspectRatio, nearZ: nearZ, farZ: farZ)
		self.fovyRadians = fovyRadians
		self.aspectRatio = aspectRatio
		self.nearZ = nearZ
		self.farZ = farZ
		
		uniformsNeedUpdate = true
	}
	
	private func updateUniforms() {
		_uniforms.viewMatrix = matrix4x4_translation(-x, -y, -z)
		_uniforms.viewProjectionMatrix = _uniforms.projectionMatrix * _uniforms.viewMatrix
		
		uniformsNeedUpdate = false
	}
	
	func updateAutoScrolling(deltaTime: Float) {
		let scrollMask = autoScrollMask

		func add(_ v: Float, to x: inout Float, forDirection direction: CameraAutoScrollMask) {
			if scrollMask.contains(direction) {
				x += v
			}
		}
		
		let posChange = deltaTime * scrollspeed
		
		add(-posChange, to: &x, forDirection: .left)
		add(posChange, to: &x, forDirection: .right)
		add(posChange, to: &y, forDirection: .up)
		add(-posChange, to: &y, forDirection: .down)
		add(-posChange, to: &z, forDirection: .forward)
		add(posChange, to: &z, forDirection: .backward)
	}
	
	func startMoving(directions: CameraAutoScrollMask) {
		autoScrollMask = autoScrollMask.union(directions)
	}
	
	func stopMoving(directions: CameraAutoScrollMask) {
		autoScrollMask = autoScrollMask.subtracting(directions)
	}
}

struct CameraAutoScrollMask: OptionSet {
	let rawValue: Int
	
	static let left = CameraAutoScrollMask(rawValue: 1 << 0)
	static let right = CameraAutoScrollMask(rawValue: 1 << 1)
	static let up = CameraAutoScrollMask(rawValue: 1 << 2)
	static let down = CameraAutoScrollMask(rawValue: 1 << 3)
	static let forward = CameraAutoScrollMask(rawValue: 1 << 4)
	static let backward = CameraAutoScrollMask(rawValue: 1 << 5)
}
