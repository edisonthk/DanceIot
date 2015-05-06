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
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var str = "hello";
        var data: NSData = str.dataUsingEncoding(NSUTF8StringEncoding, allowLossyConversion: false)!;
        print(data.length);
        print(UnsafePointer<UInt8>(data.bytes));
        
//        var fileURL = NSBundle.mainBundle().URLForResource("image", withExtension: "png")
        myImage.image = UIImage(named: "makefg");

        
        var leftLegHandler = LeftLegHandler(controller: self);
//        var rightLegHandler = RightLegHandler(controller: self);
        
    }

    @IBAction func touchUpInside(sender: AnyObject) {
        println("touched");
    }

}

