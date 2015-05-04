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
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        var leftLegHandler = LeftLegHandler(controller: self);
        var rightLegHandler = RightLegHandler(controller: self);
        
    }

    @IBAction func touchUpInside(sender: AnyObject) {
        println("touched");
    }

}

