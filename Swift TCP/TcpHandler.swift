//
//  TcpHandler.swift
//  Swift TCP
//
//  Created by Edisonthk on 2015/05/05.
//  Copyright (c) 2015年 test. All rights reserved.
//

import CoreFoundation;
import UIKit

class TcpHandler : NSObject, NSStreamDelegate{
    
    func initTcpNetwork(host:String,port :UInt32,delegate:NSStreamDelegate? ) {
        printQueueLabel();
        var readStream:  Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(nil, host, port, &readStream, &writeStream);
        
        var inputStream: NSInputStream = readStream!.takeRetainedValue();
        var outputStream: NSOutputStream = writeStream!.takeRetainedValue();
        
        inputStream.delegate = delegate;
        outputStream.delegate = delegate;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)){
            self.printQueueLabel();
            let loop = NSRunLoop.currentRunLoop();
            inputStream.scheduleInRunLoop(loop, forMode: NSDefaultRunLoopMode);
            outputStream.scheduleInRunLoop(loop, forMode: NSDefaultRunLoopMode);
            inputStream.open()
            outputStream.open()
            loop.run();
        }
        
    }
    
    func printQueueLabel(function:String = __FUNCTION__){
        let label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        println("\(function) @ \(String.fromCString(label))");
    }

    
    func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        printQueueLabel();
        switch (eventCode){
        case NSStreamEvent.OpenCompleted:
            NSLog("Stream opened");
            break
        case NSStreamEvent.HasBytesAvailable:
            var inputstream = aStream as? NSInputStream;
            
            var buffer = [UInt8](count: 4096, repeatedValue: 0);
            while ((inputstream?.hasBytesAvailable) != nil) {
                var len = inputstream?.read(&buffer, maxLength: 4096);
                if (len > 0) {
                    var output: NSString = NSString(bytes:&buffer, length:len!, encoding:NSASCIIStringEncoding)!;
                    dispatch_async(dispatch_get_main_queue(), {
                        self.handleDataReceived(output);
                    })
                }
            }
            break
        case NSStreamEvent.ErrorOccurred:
            NSLog("ErrorOccurred")
            break
        case NSStreamEvent.EndEncountered:
            NSLog("EndEncountered")
            break
        default:
            NSLog("unknown.")
        }
    }
    
    func handleDataReceived(recv: NSString) {
        
        
    }
    

}