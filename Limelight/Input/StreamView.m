//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamView.h"
#include <Limelight.h>
#import "OnScreenControls.h"
#import "DataManager.h"
#import "ControllerSupport.h"

@implementation StreamView {
    CGPoint touchLocation;
    BOOL touchMoved;
    OnScreenControls* onScreenControls;
    
    float xDeltaFactor;
    float yDeltaFactor;
    float screenFactor;
    
    int hostWidth;
    int hostHeight;
    int uiWidth;
    int uiHeight;
    float xMagicFactor;
    float yMagicFactor;
    int buttonPressed;
    BOOL touchScreenMode;
    BOOL mouseEnabled;
}

- (void) setMouseDeltaFactors:(float)x y:(float)y {
    xDeltaFactor = x;
    yDeltaFactor = y;
    
    screenFactor = [[UIScreen mainScreen] scale];
}

- (void) setTouchScreenFactors:(int)x y:(int)y {
    CGRect screenBounds = [[UIScreen mainScreen] bounds];
    
    uiWidth = screenBounds.size.width;
    uiHeight = screenBounds.size.height;
    
    // Ideally we would be able to get this when we connect to the stream
    // and whenever the host changes resolutions, but I don't think the
    // stream server ever notifies the client, so we may have to make this
    // configurably from the StreamConfiguration.
    hostWidth = 1280; //TODO: How do I get this?
    hostHeight = 720; //TODO: How do I get this?
    
    // Based on multiple resolution testing it appears that the mapped mouse space
    // available for use in the NV_MOUSE_MOVE_PACKET is exactly 3/8ths of the host
    // resolution being streamed.  So if we calculate the "mouse resolution" and
    // then divide that by the iOS "touch resolution" we get a ratio that can be
    // used to map native screen touches to host server mouse locations.
    xMagicFactor = hostWidth * 3.0 / 8.0 / uiWidth;
    yMagicFactor = hostHeight * 3.0 / 8.0 / uiHeight;
    
    // Enable automatically
    touchScreenMode = true;
}

- (void) setupOnScreenControls:(ControllerSupport*)controllerSupport swipeDelegate:(id<EdgeDetectionDelegate>)swipeDelegate {
    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport swipeDelegate:swipeDelegate];
    DataManager* dataMan = [[DataManager alloc] init];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[[dataMan retrieveSettings].onscreenControls integerValue];
    
    if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    Log(LOG_D, @"Touch down");
    if (![onScreenControls handleTouchDownEvent:touches]) {
        UITouch *touch = [[event allTouches] anyObject];
        touchLocation = [touch locationInView:self];
        touchMoved = false;
        if (touchScreenMode)
        {
            // Move the mouse to the bottom corner to sync position
            // TODO: Use StreamConfiguration to get maximum value needed
            //       to move mouse to lower corner.
            LiSendMouseMoveEvent(-9999, -9999);
            usleep(1000);
            
            // Move mouse to mapped location
            int deltaX = touchLocation.x * xMagicFactor;
            int deltaY = touchLocation.y * yMagicFactor;
            Log(LOG_D, @"Host : %d,%d", hostWidth, hostHeight);
            Log(LOG_D, @"UI : %d,%d", uiWidth, uiHeight);
            Log(LOG_D, @"Screen : %f", screenFactor);
            Log(LOG_D, @"Magic Factor X/Y: %f,%f", xMagicFactor, yMagicFactor);
            Log(LOG_D, @"Delta Factor X/Y: %f,%f", xDeltaFactor, yDeltaFactor);
            Log(LOG_D, @"Touch X/Y: %f,%f", touchLocation.x, touchLocation.y);
            Log(LOG_D, @"Delta X/Y: %d,%d", deltaX, deltaY);
            LiSendMouseMoveEvent(deltaX, deltaY);
            
            // Send button press
            if ([[event allTouches] count]  == 2) {
                Log(LOG_D, @"Sending right mouse button press");
                buttonPressed = BUTTON_RIGHT;
            } else {
                Log(LOG_D, @"Sending left mouse button press");
                buttonPressed = BUTTON_LEFT;
            }
            LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, buttonPressed);
        }
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (![onScreenControls handleTouchMovedEvent:touches]) {
        if ([[event allTouches] count] == 1) {
            UITouch *touch = [[event allTouches] anyObject];
            CGPoint currentLocation = [touch locationInView:self];
            
            if (touchLocation.x != currentLocation.x ||
                touchLocation.y != currentLocation.y)
            {
                int deltaX = currentLocation.x - touchLocation.x;
                int deltaY = currentLocation.y - touchLocation.y;
                
                if (touchScreenMode)
                {
                    deltaX = touchLocation.x * xMagicFactor;
                    deltaY = touchLocation.y * yMagicFactor;
                }
                else
                {
                    deltaX *= xDeltaFactor * screenFactor;
                    deltaY *= yDeltaFactor * screenFactor;
                }
                
                Log(LOG_D, @"Touch X/Y: %f,%f", touchLocation.x, touchLocation.y);
                Log(LOG_D, @"Delta X/Y: %d,%d", deltaX, deltaY);
                
                if (deltaX != 0 || deltaY != 0) {
                    if (touchScreenMode)
                    {
                        // This helps sync the mouse position but can cause a little
                        // stutter sometimes when performing a mouse drag.  It should
                        // be possible to calculate the delta above without needing
                        // this, but in my testing this method felt better because
                        // the dragged item was always under my finger.
                        LiSendMouseMoveEvent(-9999, -9999);
                        usleep(1000);
                    }
                    LiSendMouseMoveEvent(deltaX, deltaY);
                    touchMoved = true;
                    touchLocation = currentLocation;
                }
            }
        } else if ([[event allTouches] count] == 2) {
            CGPoint firstLocation = [[[[event allTouches] allObjects] objectAtIndex:0] locationInView:self];
            CGPoint secondLocation = [[[[event allTouches] allObjects] objectAtIndex:1] locationInView:self];
            
            CGPoint avgLocation = CGPointMake((firstLocation.x + secondLocation.x) / 2, (firstLocation.y + secondLocation.y) / 2);
            if (touchLocation.y != avgLocation.y) {
                LiSendScrollEvent(avgLocation.y - touchLocation.y);
            }
            touchMoved = true;
            touchLocation = avgLocation;
        }
    }
    
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    Log(LOG_D, @"Touch up");
    if (![onScreenControls handleTouchUpEvent:touches]) {
        if (touchScreenMode)
        {
            // Release the button pressed during initial touch
            Log(LOG_D, @"Sending release mouse button press");
            LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, buttonPressed);
            return;
        }
        if (!touchMoved) {
            if ([[event allTouches] count]  == 2) {
                Log(LOG_D, @"Sending right mouse button press");
                
                LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
                
                // Wait 100 ms to simulate a real button press
                usleep(100 * 1000);
                
                LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
                
                
            } else {
                Log(LOG_D, @"Sending left mouse button press");
                
                LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
                
                // Wait 100 ms to simulate a real button press
                usleep(100 * 1000);
                
                LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
            }
        }
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
}


@end
