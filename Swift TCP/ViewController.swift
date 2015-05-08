//
//  ViewController.swift
//  Swift TCP
//
//  Created by Edisonthk on 2015/05/03.
//  Copyright (c) 2015年 test. All rights reserved.
//

import CoreFoundation;
import UIKit

class ViewController: UIViewController {
    
    @IBOutlet weak var button: UIButton!
    @IBOutlet weak var myImage: UIImageView!
    
    
    var socket1 : TCPSocket?
    var socket2 : TCPSocket?

    override func viewDidLoad() {
        super.viewDidLoad()
        

        
        
        var msg = "Hello socket";

        //        var fileURL = NSBundle.mainBundle().URLForResource("image", withExtension: "png")
        myImage.image = UIImage(named: "makefg");
        let url = NSURL(scheme: "", host: "127.0.0.1:3100", path: "/")!
        let connected: (Void) -> Void = {
            println("connected")
        }
        let receiveText: (String) -> Void = {
            println("Receive:\($0)")
        }
        //        let disconnected: disconnectedBlock_t = {
        //            println("disconnected")
        //        }
        //        let receiveData: (NSData)-> Void = {
        //            println("Receive data")
        //        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), { () -> Void in
            //Socketの初期化と受信ハンドル設定 + Socket open
            println("This is test")
            self.socket1 = TCPSocket(url: url, connect: connected, disconnect: nil, text: receiveText, data: nil)
            self.socket1?.open()
        })
    }

    @IBAction func touchUpInside(sender: AnyObject) {
        println("touched");
        self.socket1?.writeString("TouchUpInside\n");
    }

}

