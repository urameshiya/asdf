//
//  PhysicsBody.swift
//  asdf
//
//  Created by Chinh Vu on 11/23/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

typealias Vector3 = SIMD3<Float>
typealias Vector4 = SIMD4<Float>

let gravity = Vector3(0, -0.05, 0)

class PhysicsBody {
	unowned var environment: PhysicsEnvironment!
	var position = Vector3()
	private var netForce = Vector3()
	var velocity = Vector3()
	private(set) var acceleration = Vector3()
	private var restoringForces = [RestoringForce]()
	var auditor: PhysicsBodyAuditor?
	
	func applyForce(_ force: Vector3) {
		netForce += force
	}
	
	func addRestoringForce(_ force: RestoringForce) {
		restoringForces.append(force)
	}
	
	func update() {
		auditor?.bodyWillUpdate(self)
		
		applyForce(gravity)
		restoringForces.forEach { $0.applyRestoringForce(body: self, netForce: netForce) }
		acceleration = netForce
		velocity += acceleration
		position += velocity
		
		auditor?.bodyDidUpdate(self)
		
		netForce = .zero
	}
}

protocol PhysicsBodyAuditor: AnyObject {
	func bodyWillUpdate(_ body: PhysicsBody)
	func bodyDidUpdate(_ body: PhysicsBody)
}
