//
//  LeftLegHandler.swift
//  Swift TCP
//
//  Created by Edisonthk on 2015/05/05.
//  Copyright (c) 2015年 test. All rights reserved.
//

import CoreFoundation;
import UIKit

class RightLegHandler : TcpHandler{
    
    let controller :ViewController;
    let port:UInt32 = 56330;
    let host:String = "127.0.0.1";
    
    init(controller: ViewController) {
        self.controller = controller;
        super.init();
        self.initTcpNetwork(self.host, port: self.port, delegate:self);
    }
    
    
    override func handleDataReceived(recv: NSString) {
        print(self.port, ": ", recv);
        self.controller.button.setTitle(recv, forState: UIControlState.Normal);
    }
    
}