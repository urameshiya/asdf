//
//  Pendulum.swift
//  asdf
//
//  Created by Chinh Vu on 11/21/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

class Pendulum: RestoringForce {
	var length: Float = 10
	var pivot: Vector3 = [0, 10, 0]
	weak var auditor: PendulumAuditor?
	
	func applyRestoringForce(body: PhysicsBody, netForce: Vector3) {
		let vBodyToPivot = pivot - body.position
		let d2 = length_squared(vBodyToPivot)
		let d = sqrt(d2)
		if d < length {
			return
		}
		let speed = dot(vBodyToPivot, body.velocity)
		let ext = dot(netForce, vBodyToPivot)
		let driftCorrection = (d - length) * 0.05
		let lamb = (-ext - speed) / d2 + driftCorrection
		body.applyForce(vBodyToPivot * lamb)
	}
}

class PendulumAuditor: PhysicsBodyAuditor {
	let pendulum: Pendulum
	
	init(pendulum: Pendulum) {
		self.pendulum = pendulum
		pendulum.auditor = self
	}
	
	var logSHMCoeffPromise: Promise<PhysicsBody>!
	
	func bodyWillUpdate(_ body: PhysicsBody) {
		let position = body.position
		logSHMCoeffPromise = Promise<PhysicsBody> { [pendulum] newBody in
			let hypot = distance(position, pendulum.pivot)
			let opp = abs(position.x - pendulum.pivot.x)
			let angle = asin(opp/hypot)
			let a = length(newBody.acceleration)
			print("k: \(a / angle)")
		}
	}
	
	func bodyDidUpdate(_ body: PhysicsBody) {
		logSHMCoeffPromise.fulfill(with: body)
	}
}

struct Promise<Values> {
	private var onFulfilled: (Values) -> Void
	private var fulfilled = false
	init(_ onFulfilled: @escaping (Values) -> Void) {
		self.onFulfilled = onFulfilled
	}
	
	func fulfill(with v: Values) {
		if fulfilled { return }
		onFulfilled(v)
	}
}

protocol RestoringForce {
	func applyRestoringForce(body: PhysicsBody, netForce: Vector3)
}

class PhysicsEnvironment {
	var timestep: Float = 0.3
}
