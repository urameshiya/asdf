//
//  Camera.swift
//  asdf
//
//  Created by Chinh Vu on 12/14/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

class Camera {
	var x: Float = 0
	var y: Float = 4
	var z: Float = 0
	var scrollspeed: Float = 10 // per second
	var autoScrollMask: CameraAutoScrollMask = []
	
	func viewMatrix() -> matrix_float4x4 {
		return matrix4x4_translation(-x, -y, -z)
	}
	
	func update(deltaTime: Float) {
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
