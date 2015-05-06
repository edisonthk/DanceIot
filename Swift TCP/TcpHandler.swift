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
    
    var inputstream: NSInputStream?;
    var outputstream: NSOutputStream?;
    
    
    var sendFlag:Bool = true;
    
    
    
    func initTcpNetwork(host:String,port :Int,delegate:NSStreamDelegate? ) {
//        printQueueLabel();

        NSStream.getStreamsToHostWithName(host, port: port, inputStream: &inputstream, outputStream: &outputstream)
        
        inputstream?.delegate=self;
        outputstream?.delegate=self;

        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0)){
            self.printQueueLabel();
            let loop = NSRunLoop.currentRunLoop();
            self.inputstream?.scheduleInRunLoop(loop, forMode: NSDefaultRunLoopMode);
            self.outputstream?.scheduleInRunLoop(loop, forMode: NSDefaultRunLoopMode);
            self.inputstream?.open()
            self.outputstream?.open()
            loop.run();
        
        }
        
    }
    
    func printQueueLabel(function:String = __FUNCTION__){
        let label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
        println("\(function) @ \(String.fromCString(label))");
    }
    
    func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
//        printQueueLabel();
        switch (eventCode){
        case NSStreamEvent.OpenCompleted:
            NSLog("Stream opened");
            break
        case NSStreamEvent.HasSpaceAvailable:
            NSLog("has space");
            if(sendFlag) {
                sendFlag = false;
                var outputstream = aStream as? NSOutputStream;
                var str = "0";
                
                var data: NSData = str.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!;
                outputstream?.write(UnsafePointer<UInt8>(data.bytes), maxLength: data.length);
            }
            
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
            var err = aStream.streamError;
            print(err?.description);
            
            break
        case NSStreamEvent.EndEncountered:
            aStream.close();
            aStream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode);
            break
        default:
            NSLog("unknown.")
        }
    }
    
    func handleDataReceived(recv: NSString) {
        
        
    }
    

}