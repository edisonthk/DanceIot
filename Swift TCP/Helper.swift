//
//  Helper.swift
//  Swift TCP
//
//  Created by lelect on 2015/05/08.
//  Copyright (c) 2015年 test. All rights reserved.
//

import Foundation

struct Log{
    //warm
    static func w(_ obj:AnyObject!="", f:String=__FUNCTION__,l:Int=__LINE__){
        println("[WARN :\(f)@\(l)] \(obj)")
    }
    //info
    static func i(_ obj:AnyObject!="", f:String=__FUNCTION__,l:Int=__LINE__){
        println("[INFO :\(f)@\(l)] \(obj)")
    }
    //error
    static func e(_ obj:AnyObject!="", f:String=__FUNCTION__,l:Int=__LINE__){
        println("[ERROR:\(f)@\(l)] \(obj)")
    }
}
