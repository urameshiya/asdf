//
//  TextRenderer.swift
//  asdf
//
//  Created by Chinh Vu on 11/13/20.
//  Copyright © 2020 urameshiyaa. All rights reserved.
//

import MetalKit
import IOSurface

class TextRenderer {
	init() {
		let string = "A B C D"
		let keys: [IOSurfacePropertyKey: Any] = [
			.width: 300,
			.height: 100,
			.pixelFormat: k32RGBAPixelFormat,
			.bytesPerElement: 4
		]
		let surface = IOSurface(properties: keys)!
		print(surface.bytesPerRow)
		surface.lock(options: [], seed: nil)
		let context = CGContext(data: surface.baseAddress,
								width: surface.width,
								height: surface.height,
								bitsPerComponent: 8,
								bytesPerRow: surface.bytesPerRow,
								space: CGColorSpaceCreateDeviceRGB(),
								bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

		let layer = CATextLayer()
		layer.string = string
		layer.contentsScale = 2.0
		context.scaleBy(x: 2, y: 2)
		layer.backgroundColor = NSColor.red.cgColor
		layer.frame = CGRect(x: 0, y: 0, width: 10, height: 50)
		layer.draw(in: context)
		surface.unlock(options: [], seed: nil)

		let newLayer = CALayer()
//		newLayer.contentsScale = 2.0
		newLayer.contents = surface
//		newLayer.backgroundColor = NSColor.green.cgColor
		
		let view = NSView()
		view.layer = newLayer
		view.wantsLayer = true
		
		newLayer.frame = CGRect(x: 0, y: 0, width: 300, height: 100)
		
		let window = NSWindow()
		window.contentView = view
		window.makeKeyAndOrderFront(nil)
		
		let view2 = NSView()
		view2.layer = layer
		view2.wantsLayer = true
				
		let window2 = NSWindow()
		window2.contentView = view2
		window2.makeKeyAndOrderFront(nil)
		
		window2.setContentSize(.init(width: 300, height: 100))
		window.setContentSize(.init(width: 150, height: 50))

	}
}
