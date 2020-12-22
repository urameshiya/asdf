//
//  Pointer.swift
//  asdf
//
//  Created by Chinh Vu on 12/21/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Foundation

struct AnyMutablePointer<Member> {
	let count: Int
	private let get: (Int) -> Member
	private let set: (Int, Member) -> Void
	
	init<P>(_ pointer: P) where P: MutableBufferPointerType, P.Element == Member {
		get = { i in pointer[i] }
		set = { i, newValue in pointer[i] = newValue }
		count = pointer.count
	}
	
	subscript(i: Int) -> Member {
		get {
			return get(i)
		}
		nonmutating set {
			set(i, newValue)
		}
	}
}

protocol MutableBufferPointerType {
	associatedtype Element
	
	var count: Int { get }
	
	subscript(i: Int) -> Element { get nonmutating set }
}

struct MemberMutablePointer<Parent, Member>: MutableBufferPointerType {
	let keypath: WritableKeyPath<Parent, Member>
	var pointer: UnsafeMutableBufferPointer<Parent>
	
	init(pointer: UnsafeMutableBufferPointer<Parent>, keypath: WritableKeyPath<Parent, Member>) {
		self.keypath = keypath
		self.pointer = pointer
	}
	
	var count: Int {
		pointer.count
	}
	
	subscript(i: Int) -> Member  {
		get {
			return pointer[i][keyPath: keypath]
		}
		nonmutating set {
			pointer[i][keyPath: keypath] = newValue
		}
	}
}

extension UnsafeMutableBufferPointer: MutableBufferPointerType {
	func accessing<Child>(_ keypath: WritableKeyPath<Element, Child>) -> MemberMutablePointer<Element, Child> {
		return .init(pointer: self, keypath: keypath)
	}
}
