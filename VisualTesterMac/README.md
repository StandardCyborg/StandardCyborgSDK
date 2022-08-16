# VisualTesterMac

You can feed a trace obtained from `TrueDepthFusion` into this program, and reconstruct a fused point cloud from it. 

# Running SCEyewear to get data (sample data included in project)
```
// Running SCEyewear Demo
git clone git@github.com:StandardCyborg/SCEyewearDemo.git
cd SCEyewearDemo
pod update
open *.xcw*
// run app on a device, login, click "find your fit" in top and go through flow.
// - Diagnostics will airdrop a zip to your computer you can run in VisualTesterMac later
// - Upload scene will upload it to your personal scene folder, this is not directly accessible in UI, but you can replace scans for scenes to nav there directly
```

# Running VisualTesterMac to process data
```
// Running diagnostic output through VisualTesterMac
// open StandardCyborgSDK directory
cd VisualTesterMac
// swap contents with the contents of the zip you airdropped
cd ../..
open *.xc*
// run VisualTesterMac target
// With VisualTesterMac selected, use navbar: File -> Experiment or "⌘E"
// Then click "Do Something" and watch logs in xcode
// A lot of interesting data is outputted to /tmp
open /tmp
```

I suggest running in DEBUG mode to get the most outputs by editing your scheme:
- Edit Scheme -> Build Configuration: Debug