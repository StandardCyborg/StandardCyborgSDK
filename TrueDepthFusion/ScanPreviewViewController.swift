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
    
    
    private var shaderModifier: String = """
        #pragma arguments
        float3 param;
    
        #pragma declaration
    
    
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

    
        #pragma transparent
        #pragma body

                
            float4 transformed_position = scn_frame.inverseViewTransform * float4(_surface.position, 1.0);
    
                        float3 p;
                                    p.r = transformed_position.r + 0.1;
                                    p.g =  transformed_position.g + 0.1;
                                    p.b = transformed_position.b + 0.1;
                                    p = p * 450.0;
    
                        float noise =  snoise(p ); //+ 0.6;
                

            float t = param.x; // from 0 to 1

    /*
        float t = lazerCol.z; // from 0 to 1

        float minY = lazerCol.x;
        float maxY = lazerCol.y;

        float myY = (_surface.position.y - minY) / (maxY - minY); // go from 0 to 1 from bottom to top of mesh.
    
      
    
       // if (t < myY) { // dissolve from up to down as t goes from 0 to 1.
      //      discard_fragment();
     //   }

    
    
    
                    float3 p;
                                p.r = transformed_position.r + 0.1;
                                p.g =  transformed_position.g + 0.1;
                                p.b = transformed_position.b + 0.1;
                                p = p * 19.0;
            
                    // in -1 to +1 range.
            
            
              //  _output.color.rgba = float4(noise, 0.0, 0.0, 1.0);
           
          
            float remap = noise - 0.6; // in range -1 to +1
    
            float cutoff_height = t; // t goes from 0 to 1
    //        cutoff_height = 0.5; // ok while testing.
    
            float add = 2.0 * cutoff_height + remap; // goes from -1 to +1 as time goes by.
    
            if(add > 1.0) {
                add = 1.0;
            }
    
            //float myY = (_surface.position.y - minY) / (maxY - minY); // go from 0 to 1 from bottom to top of mesh.
    
            if(add > -1.0 + 2.0 * myY) {
    
                    if(add < -1.0 + 2.0 * myY + 0.07) {
                        //_output.color.rgb = float3(  10.0, 0.0, 0.0);
    
                                _output.color.rgb = 4.0 * float3(173.0 / 255, 216.0 / 255.0, 230.0 / 255.0);
    
                    }

                //_output.color.rgba = float4(1.0, 0.0, 0.0, 1.0);
    
         
            } else {
                    discard_fragment();
               // _output.color.rgba = float4(0.0, 1.0, 0.0, 1.0);
            }
    
    
    
            //cutoff_height
            
            float step = 1000.0;
    
            if(myY > add) {
                step = 1.0;
            } else {
                step = 0.0;
            }
    
            if(step > 0.90) {
            } else {
    //            discard_fragment();
            }
    
    
    
    
          //  float3 col = 0.0;
    
            //  col = float3(remap, 0.0, 0.0);
    
    
    float3 col =_output.color.rgb;;
                
    col = float3(step, 0.0, 0.0);
        
        
    
        _output.color.rgb = col;
    */
    
            float3 col = float3(0., 0.0, 0.0);
    
    //            float val = random(p);
            float val = (noise + 1.0) * 0.5 ;
    /*
            if(val > 1.0) {
                val = 1.0;
            }
    
            if(val < 0.0) {
                val = 0.0;
            }
    */
    
            if(val < 0.0) {
                col = float3(1.0, 0.0, 0.0);
            } else if(0.0 <= val && val < 0.4) {
                col = float3(0.0, 1.0, 0.0);
            }else if(0.4 <= val && val < 0.8) {
                col = float3(0.0, 0.0, 1.0);
            }else if(0.8 <= val && val < 1.0) {
                col = float3(1.0, 1.0, 0.0);
            }else if(1.0 <= val) {
                col = float3(0.3, 0.3, 0.3);
            }
    
            //_output.color.rgb = float3(1.0, 0.0, 0.0) * _output.color.rgb;
            //_output.color.rgb = col;
    
            /*
            _output.color.rgb = float3(val);
                _output.color.rgb = float3(val);
    
    
            _output.color.rgb = float3(1.0, 0.0, 0.0);
            _output.color.a = 0.5;
    */
    
            if(val > t) {
                 discard_fragment();
            } else {
                
            }
    
               // _output.color.rgb = float3(t, 0.0, 0.0);
                

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
        guard let scan = scan else { return }
        
        /*
        meshingProgressContainer.isHidden = false
        meshingProgressContainer.alpha = 0
        meshingProgressView.progress = 0
        */
        
        UIView.animate(withDuration: 0.4) {
            self.meshingProgressContainer.alpha = 1
        }
        
        let meshingParameters = SCMeshingParameters()
        meshingParameters.resolution = 5
        meshingParameters.smoothness = 1
        meshingParameters.surfaceTrimmingAmount = 5
        meshingParameters.closed = true
        
        let textureResolutionPixels = 2048
        
        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: textureResolutionPixels,
            meshingParameters: meshingParameters,
            coloringStrategy: .vertex,
            progress: { percentComplete, shouldStop in
                DispatchQueue.main.async {
                    self.meshingProgressView.progress = percentComplete
                }
                
                shouldStop.pointee = ObjCBool(self._shouldCancelMeshing)
            },
            completion: { error, scMesh in
                if let error = error {
                    print("Meshing error: \(error)")
                }
                
                DispatchQueue.main.async {
                    self.meshingProgressContainer.isHidden = true
                    self._shouldCancelMeshing = false
                    
                    if let mesh = scMesh {
                        let node = mesh.buildMeshNode()
                        node.transform = self._pointCloudNode?.transform ?? SCNMatrix4Identity
                        self._pointCloudNode = node
                        self._mesh = mesh
                        
                        
                        
                        
                    }
                }
            }
        )
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
        
        self._pointCloudNode?.isHidden = true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if let scan = scan, scan.thumbnail == nil {
            let snapshot = sceneView.snapshot()
            scan.thumbnail = snapshot.resized(toWidth: 640)
        }
        
        
        
        
        
        guard let scan = scan else { return }
        
        
        //meshingProgressContainer.isHidden = false
        //meshingProgressContainer.alpha = 0
        //meshingProgressView.progress = 0
        
        
        UIView.animate(withDuration: 0.4) {
            //self.meshingProgressContainer.alpha = 1
            
        }
        
        let meshingParameters = SCMeshingParameters()
        meshingParameters.resolution = 4
        meshingParameters.smoothness = 1
        meshingParameters.surfaceTrimmingAmount = 5
        meshingParameters.closed = true
        
        let textureResolutionPixels = 2048
        
        scan.meshTexturing.reconstructMesh(
            pointCloud: scan.pointCloud,
            textureResolution: textureResolutionPixels,
            meshingParameters: meshingParameters,
            coloringStrategy: .vertex,
            progress: { percentComplete, shouldStop in
                DispatchQueue.main.async {
                    self.meshingProgressView.progress = percentComplete
                }
                
                shouldStop.pointee = ObjCBool(self._shouldCancelMeshing)
            },
            completion: { error, scMesh in
                if let error = error {
                    print("Meshing error: \(error)")
                }
                
                DispatchQueue.main.async {
                    self.meshingProgressContainer.isHidden = true
                    self._shouldCancelMeshing = false
                    
                
                    if let mesh = scMesh {
                        let node = mesh.buildMeshNode()
                        node.transform = self._pointCloudNode?.transform ?? SCNMatrix4Identity
                        self._pointCloudNode = node
                        self._mesh = mesh
                        
                        guard let geometry = node.geometry else { return }
                                
                                
                        geometry.shaderModifiers = [ .fragment: self.shaderModifier ]
                        
                        // Add a custom material to use the shader
                        let material = SCNMaterial()
                        material.diffuse.contents = UIColor.white
                        material.isDoubleSided = false
                        
                        material.setValue(SCNVector3(0.0, 0.0, 0.0), forKey: "param")
                        
                        
                        let timeAction = SCNAction.customAction(duration: 5.0) { (node, elapsedTime) in
                            
                            
                            var t = elapsedTime / 2.5
                            
                            if(t > 1.0) {
                                t = 1.0
                            }
                            var vv =  SCNVector3(t, 0.0, 0.0 )
                             
                           // print("vv ", vv)
                            node.geometry?.firstMaterial?.setValue(vv, forKey: "param")
                           
                        }
                        
                        //SCNAction.repeat(timeAction, count: 1)
                        
                        let repeatAction = SCNAction.repeatForever(timeAction)
                        node.runAction(repeatAction)

                        
                        geometry.materials = [material]
                        
                        
                    }
                    
                    
                    
                }
            }
        )
        
        
    }
    
    // MARK: - Public
    
    var scan: Scan? {
        didSet {
            _pointCloudNode = scan?.pointCloud.buildNode()
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
    
}
