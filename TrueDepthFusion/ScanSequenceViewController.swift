//
//  ScanSequenceViewController.swift
//  TrueDepthFusion
//
//  Created by Aaron Thompson on 3/9/19.
//  Copyright © 2019 Standard Cyborg. All rights reserved.
//

import SceneKit
import UIKit

class ScanSequenceViewController: UIViewController {
    
    var accumulator: BPLYDepthDataAccumulator!
    
    private let _device = MTLCreateSystemDefaultDevice()!
    private lazy var _library = _device.makeDefaultLibrary()!
    private lazy var _pointCloudRenderer = SCPointCloudRenderer(device: _device, library: _library)
    private lazy var _commandQueue = _device.makeCommandQueue()!
    private let _metalLayer = CAMetalLayer()
    private let _sceneView = SCNView()
    private var _playing = false
    
    override func viewDidLoad() {
        _metalLayer.device = _device
        _metalLayer.isOpaque = true
        _metalLayer.contentsScale = UIScreen.main.scale
        _metalLayer.pixelFormat = MTLPixelFormat.bgra8Unorm
        _metalLayer.framebufferOnly = false
        _metalLayer.frame = view.bounds
        view.layer.addSublayer(_metalLayer)
        view.backgroundColor = UIColor.blue
        
        _sceneView.scene = SCNScene(named: "ScanPreviewViewController.scn")
        _sceneView.backgroundColor = UIColor.yellow
        _sceneView.allowsCameraControl = true
        view.addSubview(_sceneView)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(_viewTapped(_:)))
        view.addGestureRecognizer(tapRecognizer)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self._loadNextFrame(andAutoLoadNext: false)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        CATransaction.begin()
        CATransaction.disableActions()
        _metalLayer.frame = view.bounds
        _metalLayer.drawableSize = CGSize(width: _metalLayer.frame.width   * _metalLayer.contentsScale,
                                          height: _metalLayer.frame.height * _metalLayer.contentsScale)
        CATransaction.commit()
        
        _sceneView.frame = view.bounds
    }
    
    @objc private func _viewTapped(_ sender: Any?) {
        if _playing {
            self.dismiss(animated: true) {
                try? FileManager.default.removeItem(atPath: self.accumulator.containerPath())
            }
        } else {
            _playing = true
            _loadNextFrame(andAutoLoadNext: true)
        }
    }
    
    @objc private func _loadNextFrame(andAutoLoadNext autoLoadNext: Bool) {
        DispatchQueue.global(qos: DispatchQoS.QoSClass.userInitiated).async {
            let pointCloudNode = self.accumulator.loadNextPointCloud()?.buildNode()
            
            // LAME: In the absence of setting up a display link and being fancy, keep things from
            //       looking super sped up by pausing for a frame, to match up with 30 FPS recording
            Thread.sleep(forTimeInterval: 1.0/60.0)
            
            DispatchQueue.main.async {
                if pointCloudNode != nil {
                    self._pointCloudNode = pointCloudNode
                } else {
                    self.accumulator.resetNextPointCloud()
                }
                
                if autoLoadNext {
                    self._loadNextFrame(andAutoLoadNext: true)
                }
            }
        }
        
        // guard let commandBuffer = _commandQueue.makeCommandBuffer(),
        //       let drawable = _metalLayer.nextDrawable()
        // else { return }
        //
        // _pointCloudRenderer.encodeCommands(onto: commandBuffer,
        //                                    pointCloud: pointCloud,
        //                                    viewMatrix: matrix_identity_float4x4,
        //                                    outputTexture: drawable.texture,
        //                                    flipsInputHorizontally: false)
        //
        // commandBuffer.present(drawable)
        // commandBuffer.commit()
        // commandBuffer.waitUntilCompleted()
    }
    
    private var _pointCloudNode: SCNNode? {
        willSet {
            _pointCloudNode?.removeFromParentNode()
        }
        didSet {
            _pointCloudNode?.name = "point cloud"
            
            // Make sure the view is loaded first
            _ = self.view
            
            if let node = _pointCloudNode {
                _sceneView.scene!.rootNode.addChildNode(node)
            }
        }
    }
}
