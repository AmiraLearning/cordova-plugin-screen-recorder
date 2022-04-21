/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at

 http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import <Cordova/CDV.h>
#import "ScreenRecorder.h"
#import <UIKit/UIKit.h>
#import <ReplayKit/ReplayKit.h>

@interface ScreenRecorder () {}
@property (strong, nonatomic) NSString *assetId;
@property (strong, nonatomic) RPScreenRecorder *screenRecorder;
@property (strong, nonatomic) AVAssetWriter *assetWriter;
@property (strong, nonatomic) AVAssetWriterInput *assetWriterInput;
@end

@implementation ScreenRecorder

- (void)startRecording:(CDVInvokedUrlCommand *)command {
    self.assetId = [NSString stringWithFormat:@"%u", arc4random() % 1000];
    
    NSError *error = nil;
    // NSTemporaryDirectory()
    NSString *videoOutPath = [[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:self.assetId] stringByAppendingPathExtension:@"mp4"];
    self.assetWriter = [AVAssetWriter assetWriterWithURL:[NSURL fileURLWithPath:videoOutPath] fileType:AVFileTypeMPEG4 error:&error];
    
    NSDictionary *compressionProperties = @{AVVideoProfileLevelKey         : AVVideoProfileLevelH264HighAutoLevel,
                                            AVVideoH264EntropyModeKey      : AVVideoH264EntropyModeCABAC,
                                            AVVideoAverageBitRateKey       : @(1920 * 1080 * 11.4),
                                            AVVideoMaxKeyFrameIntervalKey  : @60,
                                            AVVideoAllowFrameReorderingKey : @NO};
    
    NSDictionary *videoSettings = @{AVVideoCompressionPropertiesKey : compressionProperties,
                                    AVVideoCodecKey                 : AVVideoCodecTypeH264,
                                    AVVideoWidthKey                 : @1080,
                                    AVVideoHeightKey                : @1920};
    
    self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    
    [self.assetWriter addInput:self.assetWriterInput];
    [self.assetWriterInput setMediaTimeScale:60];
    [self.assetWriter setMovieTimeScale:60];
    [self.assetWriterInput setExpectsMediaDataInRealTime:YES];
    
    self.screenRecorder = [RPScreenRecorder sharedRecorder];
    
    [self.screenRecorder startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
        NSLog(@"ScreenRecorder: Buffer status: %@", CMSampleBufferDataIsReady(sampleBuffer));
        if (CMSampleBufferDataIsReady(sampleBuffer)) {
            if (self.assetWriter.status == AVAssetWriterStatusUnknown) {
                [self.assetWriter startWriting];
                [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
            }
            
            if (self.assetWriter.status == AVAssetWriterStatusFailed) {
                NSLog(@"ScreenRecorder: assetWriter error occured.");
                return;
            }
            
            if (bufferType == RPSampleBufferTypeVideo) {
                NSLog(@"ScreenRecorder: Found video buffertype.");
                if (self.assetWriterInput.isReadyForMoreMediaData) {
                    NSLog(@"ScreenRecorder: assetWriterInput.isReadyForMoreMediaData.");
                    [self.assetWriterInput appendSampleBuffer:sampleBuffer];
                }
            }
        }
    } completionHandler:^(NSError * _Nullable error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:self.assetId];
        if (!error) {
            NSLog(@"Recording started successfully.");
        } else {
            NSLog(@"Error starting recording.");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error starting recording."];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)stopRecording:(CDVInvokedUrlCommand *)command {
    [self.screenRecorder stopCaptureWithHandler:^(NSError * _Nullable error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:self.assetId];
        if (!error) {
            NSLog(@"Recording stopped successfully. Cleaning up...");
            if (self.assetWriter.status != AVAssetWriterStatusCompleted && self.assetWriter.status != AVAssetWriterStatusUnknown) {
                [self.assetWriterInput markAsFinished];
            }
            
            if ([self.assetWriter respondsToSelector:@selector(finishWritingWithCompletionHandler:)]) {
                [self.assetWriter finishWritingWithCompletionHandler:^{
                    self.assetWriterInput = nil;
                    self.assetWriter = nil;
                    self.screenRecorder = nil;
                }];
            } else {
                [self.assetWriter finishWriting];
            }
            
            // Save the video photo library
//                        PHPhotoLibrary.shared().performChanges({
//                            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: self.videoOutputURL)
//                        }) { saved, error in
//                            if saved {
//                                let alertController = UIAlertController(title: "Your video was successfully saved", message: nil, preferredStyle: .alert)
//                                let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
//                                alertController.addAction(defaultAction)
//                                self.present(alertController, animated: true, completion: nil)
//                            }
//                            if error != nil {
//                                os_log("Video did not save for some reason", error.debugDescription);
//                                debugPrint(error?.localizedDescription ?? "error is nil");
//                            }
//                        }
            
        } else {
            NSLog(@"Error stopping recording.");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error stopping recording."];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

@end
