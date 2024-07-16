//
//  ScanPreviewViewController.swift
//  DepthRenderer
//
//  Created by Aaron Thompson on 5/11/18.
//  Copyright © 2019 Standard Cyborg. All rights reserved.
//

import Foundation
import ModelIO
import QuickLook
import StandardCyborgFusion
import SceneKit
import UIKit

class ScanPreviewViewController: UIViewController, QLPreviewControllerDataSource {
    
    // MARK: - IB Outlets and Actions
    
    @IBOutlet private weak var sceneView: SCNView!
    @IBOutlet private weak var meshButton: UIButton!
    @IBOutlet private weak var meshingProgressContainer: UIView!
    @IBOutlet private weak var meshingProgressView: UIProgressView!
    
    private var _quickLookUSDZURL: URL?
    
    
    private var dissolveAnimationShaderModifier: String = """
    
        #pragma arguments
        float3 param;
    
        #pragma declaration
    
    //
    // Description : Array and textureless GLSL 2D/3D/4D simplex
    //               noise functions.
    //      Author : Ian McEwan, Ashima Arts.
    //  Maintainer : ijm
    //     Lastmod : 20110822 (ijm)
    //     License : Copyright (C) 2011 Ashima Arts. All rights reserved.
    //               Distributed under the MIT License. See LICENSE file.
    //               https://github.com/ashima/webgl-noise
    //

    float random(float3 pos){
        return fract(sin(dot(pos, float3(64.25375463, 23.27536534, 86.29678483))) * 59482.7542);
    }
    
    float3 mod289(float3 x) {
      return x - floor(x * (1.0 / 289.0)) * 289.0;
    }

    float4 mod289(float4 x) {
      return x - floor(x * (1.0 / 289.0)) * 289.0;
    }

    float4 permute(float4 x) {
         return mod289(((x*34.0)+1.0)*x);
    }

    float4 taylorInvSqrt(float4 r)
    {
      return 1.79284291400159 - 0.85373472095314 * r;
    }

    float snoise(float3 v)
      {
      const float2  C = float2(1.0/6.0, 1.0/3.0) ;
      const float4  D = float4(0.0, 0.5, 1.0, 2.0);

    // First corner
      float3 i  = floor(v + dot(v, C.yyy) );
      float3 x0 =   v - i + dot(i, C.xxx) ;

    // Other corners
      float3 g = step(x0.yzx, x0.xyz);
      float3 l = 1.0 - g;
      float3 i1 = min( g.xyz, l.zxy );
      float3 i2 = max( g.xyz, l.zxy );

      //   x0 = x0 - 0.0 + 0.0 * C.xxx;
      //   x1 = x0 - i1  + 1.0 * C.xxx;
      //   x2 = x0 - i2  + 2.0 * C.xxx;
      //   x3 = x0 - 1.0 + 3.0 * C.xxx;
      float3 x1 = x0 - i1 + C.xxx;
      float3 x2 = x0 - i2 + C.yyy; // 2.0*C.x = 1/3 = C.y
      float3 x3 = x0 - D.yyy;      // -1.0+3.0*C.x = -0.5 = -D.y

    // Permutations
      i = mod289(i);
      float4 p = permute( permute( permute(
                 i.z + float4(0.0, i1.z, i2.z, 1.0 ))
               + i.y + float4(0.0, i1.y, i2.y, 1.0 ))
               + i.x + float4(0.0, i1.x, i2.x, 1.0 ));

    // Gradients: 7x7 points over a square, mapped onto an octahedron.
    // The ring size 17*17 = 289 is close to a multiple of 49 (49*6 = 294)
      float n_ = 0.142857142857; // 1.0/7.0
      float3  ns = n_ * D.wyz - D.xzx;

      float4 j = p - 49.0 * floor(p * ns.z * ns.z);  //  mod(p,7*7)

      float4 x_ = floor(j * ns.z);
      float4 y_ = floor(j - 7.0 * x_ );    // mod(j,N)

      float4 x = x_ *ns.x + ns.yyyy;
      float4 y = y_ *ns.x + ns.yyyy;
      float4 h = 1.0 - abs(x) - abs(y);

      float4 b0 = float4( x.xy, y.xy );
      float4 b1 = float4( x.zw, y.zw );

      //float4 s0 = float4(lessThan(b0,0.0))*2.0 - 1.0;
      //float4 s1 = float4(lessThan(b1,0.0))*2.0 - 1.0;
      float4 s0 = floor(b0)*2.0 + 1.0;
      float4 s1 = floor(b1)*2.0 + 1.0;
      float4 sh = -step(h, float4(0.0));

      float4 a0 = b0.xzyw + s0.xzyw*sh.xxyy ;
      float4 a1 = b1.xzyw + s1.xzyw*sh.zzww ;

      float3 p0 = float3(a0.xy,h.x);
      float3 p1 = float3(a0.zw,h.y);
      float3 p2 = float3(a1.xy,h.z);
      float3 p3 = float3(a1.zw,h.w);

    //Normalise gradients
      float4 norm = taylorInvSqrt(float4(dot(p0,p0), dot(p1,p1), dot(p2, p2), dot(p3,p3)));
      p0 *= norm.x;
      p1 *= norm.y;
      p2 *= norm.z;
      p3 *= norm.w;

    // Mix final noise value
      float4 m = max(0.6 - float4(dot(x0,x0), dot(x1,x1), dot(x2,x2), dot(x3,x3)), 0.0);
      m = m * m;
      return 42.0 * dot( m*m, float4( dot(p0,x0), dot(p1,x1),
                                    dot(p2,x2), dot(p3,x3) ) );
      }
    
        //
        // END SIMPLEX NOISE IMPLEMENTATION.
        //

        #pragma transparent
        #pragma body

        float t = param.x;
    
    
        
        float4 worldspace_position = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
        
        float3 p;
        p.r = worldspace_position.r + 0.1;
        p.g = worldspace_position.g + 0.1;
        p.b = worldspace_position.b + 0.1;
        p = p * 450.0;
        
        // sample the noise function.
        float noise =  snoise(p);
        
        float val = (noise + 1.0) * 0.5 ; // val is in range [0, 1]

                // t will go from 0 to 1. thus, more and more of the mesh will be revealed
        if(val > t) {
            // dont show this fragment
            discard_fragment();
        } else {
            // DO show this fragment.
        }
     

    """
    
    @IBAction private func _export(_ sender: AnyObject) {
        if let scan = scan {
            let shareURL: URL?
            
            if _shouldExportToUSDZ {
                if let mesh = _mesh {
                    let tempUSDZPath = NSTemporaryDirectory().appending("/mesh.usdc")
                    
                    try? FileManager.default.removeItem(atPath: tempUSDZPath)
                    mesh.writeToUSDC(atPath: tempUSDZPath)
                    
                    shareURL = URL(fileURLWithPath: tempUSDZPath)
                } else {
                    shareURL = scan.writeUSDZ()
                }
            } else if let meshURL = _meshURL {
                shareURL = meshURL
            } else {
                shareURL = scan.writeCompressedPLY()
            }
            
            if let shareURL = shareURL {
                _quickLookUSDZURL = shareURL
                // let controller = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
                // controller.popoverPresentationController?.sourceView = sender as? UIView
                // present(controller, animated: true, completion: nil)
                let controller = QLPreviewController()
                controller.dataSource = self
                controller.modalPresentationStyle = .overFullScreen
                self.present(controller, animated: true, completion: nil)
            }
        }
    }
    
    // MARK: - QLPreviewControllerDataSource
    
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return 1
    }
    
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        return _quickLookUSDZURL! as QLPreviewItem
    }
    
    @IBAction private func _delete(_ sender: Any) {
        deletionHandler?()
    }
    
    @IBAction private func _done(_ sender: Any) {
        doneHandler?()
    }
    
    @IBAction private func _runMeshing(_ sender: Any) {
        
    }
    
    @IBAction private func cancelMeshing(_ sender: Any) {
        _shouldCancelMeshing = true
    }
    
    // MARK: - UIViewController
    
    override func viewDidLoad() {
        _initialPointOfView = sceneView.pointOfView!.transform
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        sceneView.pointOfView!.transform = _initialPointOfView
        meshButton.isHidden = scan?.plyPath == nil
        
        //self._pointCloudNode?.isHidden = true
        
        sceneView.scene?.rootNode.childNodes.forEach { $0.removeFromParentNode() }

        _containerNode = SCNNode()
        //_triMeshNode = SCNNode()
        //_addedTriMeshNode = false
        
        sceneView.scene?.rootNode.addChildNode(_containerNode)
        
    }
    
    private var A:Float = 0.975
    
    override func viewDidAppear(_ animated: Bool) {
        if let scan = scan, scan.thumbnail == nil {
            let snapshot = sceneView.snapshot()
            scan.thumbnail = snapshot.resized(toWidth: 640)
        }
        
        guard let scan = scan else { return }
        
        let meshingParameters = SCMeshingParameters()
        meshingParameters.resolution = 4 //4
        meshingParameters.smoothness = 1
        meshingParameters.surfaceTrimmingAmount = 5
        meshingParameters.closed = true
        
        let textureResolutionPixels = 2048 / 2
        
        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: textureResolutionPixels,
            meshingParameters: meshingParameters,
            coloringStrategy: .uvMap,
            progress: { percentComplete, shouldStop in
            },
            completion: { error, scMesh in
                if let error = error {
                    print("Meshing error: \(error)")
                    return
                }
                
                DispatchQueue.main.async {
                    
                    if let mesh = scMesh {
                        let node = mesh.buildMeshNode()
                        self._containerNode.addChildNode(node)
                        
                        self._mesh = mesh
                        
                        guard let geometry = node.geometry else { return }
                        
                        // TODO put in func.
                        let gmin = geometry.boundingBox.min
                        let gmax = geometry.boundingBox.max
                        let x_center = (gmin.x + gmax.x) * 0.5
                        let z_center = (gmin.z + gmax.z) * 0.5
                        let pivotMatrix = SCNMatrix4MakeTranslation(x_center, 0, z_center)
                        node.pivot = pivotMatrix // we make sure the mesh rotates about its own center.
                        
                        geometry.shaderModifiers = [ .fragment: self.dissolveAnimationShaderModifier ]
                        
                        // constant lighting looks best when spinning the mesh.
                        node.geometry?.firstMaterial?.lightingModel = .constant
                        
                        let A:Float = 4.5
                        
                        let dissolveAction = SCNAction.customAction(duration: 8.0) { (node, elapsedTime) in
                            
                            var at:Float = 0.0
                            
                            if(Float(elapsedTime) < 0.2) {
                                at = Float(Float(elapsedTime) / 0.2) * 0.1
                            } else if(0.2 <= Float(elapsedTime) && elapsedTime < 3.5) {
                                at = 0.1 + 0.2 *  (Float(elapsedTime) - 0.2) / (3.5 - 0.2);
                            } else if(3.5 <= Float(elapsedTime) && elapsedTime < 4.5) {
                                at = 0.30 +  0.70 * (Float(elapsedTime) - 3.5) / (4.5-3.5) ;
                            } else if(A < Float(elapsedTime) && elapsedTime < 7.0) {
                                at = 1.0
                            } else {
                                at = 1.0
                            }
                            
                            node.geometry?.firstMaterial?.setValue(SCNVector3(at, 0.0, 0.0 ), forKey: "param")
                        }
                        
                        let repeatAction = SCNAction.repeatForever(dissolveAction)
                        node.runAction(repeatAction)
                        
                        
                        // rotate mesh around its own y axis, 360 degrees.
                        let rotationAction = SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: Double(A))
                        rotationAction.timingMode = .easeInEaseOut
                        node.runAction(rotationAction)
                      
                    }
                    
                }
            }
        )
        
        
    }
    
    // MARK: - Public
    
    var scan: Scan? {
        didSet {
            //_pointCloudNode = scan?.pointCloud.buildNode()
        }
    }
    
    var deletionHandler: (() -> Void)?
    var doneHandler: (() -> Void)?
    
    // MARK: - Private
    
    private let _appDelegate = UIApplication.shared.delegate! as! AppDelegate
    private let _shouldExportToUSDZ = true
    private var _shouldCancelMeshing = false
    private var _meshURL: URL?
    private var _mesh: SCMesh?
    private var _initialPointOfView = SCNMatrix4Identity
    private var _containerNode = SCNNode()

    //private var _triMeshNode = SCNNode()
    //private var _addedTriMeshNode = false
    
    
    /*
    private var _pointCloudNode: SCNNode? {
        willSet {
            _pointCloudNode?.removeFromParentNode()
        }
        didSet {
            _pointCloudNode?.name = "point cloud"
            
            // Make sure the view is loaded first
            _ = self.view
            
            if let node = _pointCloudNode {
                sceneView.scene!.rootNode.addChildNode(node)
            }
        }
    }
    */
    
}
