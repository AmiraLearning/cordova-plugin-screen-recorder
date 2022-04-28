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
    self.assetId = [[NSUUID UUID] UUIDString];
    
    // TODO: Use temp directory instead of documents dir
    // NSTemporaryDirectory()
    NSString *videoOutPath = [[[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:self.assetId] stringByAppendingPathExtension:@"mp4"];
    
    NSURL *outputUrl = [NSURL fileURLWithPath:videoOutPath];
    NSLog(@"ScreenRecorder: video output url: %@", outputUrl);
    
    NSError *deleteError = nil;
    [[NSFileManager defaultManager] removeItemAtURL:outputUrl error:&deleteError];
    if (deleteError) {
        NSLog(@"ScreenRecorder: error deleting old file at path: %@", deleteError);
    }
    
    self.screenRecorder = [RPScreenRecorder sharedRecorder];
    [self.screenRecorder discardRecordingWithHandler:^{}];
    
    NSError *error = nil;
    self.assetWriter = [[AVAssetWriter alloc] initWithURL:outputUrl fileType:AVFileTypeMPEG4 error:&error];
    
    // TODO: Try to improve video quality by  using original settings
//    NSDictionary *compressionProperties = @{AVVideoProfileLevelKey         : AVVideoProfileLevelH264HighAutoLevel,
//                                            AVVideoH264EntropyModeKey      : AVVideoH264EntropyModeCABAC,
//                                            AVVideoAverageBitRateKey       : @(1920 * 1080 * 11.4),
//                                            AVVideoMaxKeyFrameIntervalKey  : @60,
//                                            AVVideoAllowFrameReorderingKey : @NO};
//    AVVideoCompressionPropertiesKey : compressionProperties,
    
    NSDictionary *videoSettings = @{
                                    AVVideoCodecKey                 : AVVideoCodecTypeH264,
                                    AVVideoWidthKey                 : [NSNumber numberWithFloat:UIScreen.mainScreen.bounds.size.width],
                                    AVVideoHeightKey                : [NSNumber numberWithFloat:UIScreen.mainScreen.bounds.size.height]};
    
    self.assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoSettings];
    
    [self.assetWriter addInput:self.assetWriterInput];
    // TODO: Try reimplementing this to improve video quality
//    [self.assetWriterInput setMediaTimeScale:60];
//    [self.assetWriter setMovieTimeScale:60];
    [self.assetWriterInput setExpectsMediaDataInRealTime:YES];
    
    // TODO: Add audio with audio input?
    
    [self.screenRecorder startCaptureWithHandler:^(CMSampleBufferRef  _Nonnull sampleBuffer, RPSampleBufferType bufferType, NSError * _Nullable error) {
        if (error) {
            NSLog(@"ScreenRecorder: Error starting capture: %@", error.debugDescription);
            return;
        }
        if (CMSampleBufferDataIsReady(sampleBuffer)) {
            
            switch (bufferType) {
                case RPSampleBufferTypeVideo:
                    NSLog(@"ScreenRecorder: Found video buffertype.");
                    if (self.assetWriter.status == AVAssetWriterStatusUnknown) {
                        NSLog(@"ScreenRecorder: Starting asset writer writing");
                        [self.assetWriter startWriting];
                        [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                    }
                    
                    if (self.assetWriter.status == AVAssetWriterStatusWriting && self.assetWriterInput.isReadyForMoreMediaData) {
                        NSLog(@"ScreenRecorder: assetWriterInput.isReadyForMoreMediaData.");
                        [self.assetWriterInput appendSampleBuffer:sampleBuffer];
                    }
                    
                    if (self.assetWriter.status == AVAssetWriterStatusFailed) {
                        NSLog(@"ScreenRecorder: assetWriter error occured. Status: %ld. Error: %@", (long)self.assetWriter.status, self.assetWriter.error.debugDescription);
                    }
                    break;
                    
                default:
                    NSLog(@"ScreenRecorder: Not a supported buffer type... Ignoring.");
                    break;
            }
        }
    } completionHandler:^(NSError * _Nullable error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:self.assetId];
        if (!error) {
            NSLog(@"ScreenRecorder: Recording started successfully.");
        } else {
            NSLog(@"ScreenRecorder: Error starting recording.");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error starting recording."];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void)stopRecording:(CDVInvokedUrlCommand *)command {
    [self.screenRecorder stopCaptureWithHandler:^(NSError * _Nullable error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:self.assetId];
        if (!error) {
            NSLog(@"ScreenRecorder: Recording stopped successfully. Cleaning up...");
            if (self.assetWriter.status != AVAssetWriterStatusCompleted && self.assetWriter.status != AVAssetWriterStatusUnknown) {
                #if TARGET_OS_SIMULATOR
                    // Do nothing
                #else
                    [self.assetWriterInput markAsFinished];
                #endif
            }
            
            if ([self.assetWriter respondsToSelector:@selector(finishWritingWithCompletionHandler:)]) {
                [self.assetWriter finishWritingWithCompletionHandler:^{
                    self.assetWriterInput = nil;
                    self.assetWriter = nil;
                    self.screenRecorder = nil;
                }];
            } else {
                [self.assetWriter finishWritingWithCompletionHandler:^() {}];
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
            NSLog(@"ScreenRecorder: Error stopping recording.");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Error stopping recording."];
        }
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

@end
