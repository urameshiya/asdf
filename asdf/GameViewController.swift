//
//  GameViewController.swift
//  asdf
//
//  Created by Chinh Vu on 11/12/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import Cocoa
import MetalKit

// Our macOS specific view controller
class GameViewController: NSViewController {

    var renderer: Renderer!
    var mtkView: MTKView!

    override func viewDidLoad() {
        super.viewDidLoad()

        guard let mtkView = self.view as? MTKView else {
            print("View attached to GameViewController is not an MTKView")
            return
        }

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return
        }

        mtkView.device = defaultDevice

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)

        mtkView.delegate = renderer
		self.mtkView = mtkView
    }
		
//	override func viewDidAppear() {
//		view.window?.makeFirstResponder(self)
//	}
	
	override func keyDown(with event: NSEvent) {
		let cameraScrollDirection = getCameraScrollMask(event: event)
		
		if let direction = cameraScrollDirection {
			self.renderer.camera.startMoving(directions: direction)
			return
		}
		
		super.keyDown(with: event)
	}
	
	private func getCameraScrollMask(event: NSEvent) -> CameraAutoScrollMask? {
		switch event.charactersIgnoringModifiers?.lowercased() {
		case "w":
			return .forward
		case "s":
			return .backward
		case "a":
			return .left
		case "d":
			return .right
		case " ":
			return .up
		default:
			return nil
		}
	}
	
	override func flagsChanged(with event: NSEvent) {
		if event.modifierFlags.contains(.shift) {
			renderer.camera.startMoving(directions: .down)
		} else {
			renderer.camera.stopMoving(directions: .down)
		}
	}
	
	override func keyUp(with event: NSEvent) {
		let cameraScrollDirection = getCameraScrollMask(event: event)
		
		if let direction = cameraScrollDirection {
			self.renderer.camera.stopMoving(directions: direction)
			return
		}
		
		super.keyDown(with: event)
	}
}

