//
//  AppDelegate.m
//  VisualTesterMac
//
//  Created by Aaron Thompson on 7/10/18.
//  Copyright © 2018 Standard Cyborg. All rights reserved.
//

#import "AppDelegate.h"
#import "ExperimentWindowController.h"

@implementation AppDelegate {
    ExperimentWindowController *_experimentWC;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
}

- (IBAction)beginExperiment:(id)sender {
    [_experimentWC close];
    
    _experimentWC = [[ExperimentWindowController alloc] initWithWindowNibName:@"ExperimentWindowController"];
    [_experimentWC showWindow:nil];
}

@end
