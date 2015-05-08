import Foundation
import CoreFoundation

public protocol TCPSocketDelegate: class {
    func TCPSocketDidConnect(socket: TCPSocket)
    func TCPSocketDidDisconnect(socket: TCPSocket, error: NSError?)
    func TCPSocketDidReceiveMessage(socket: TCPSocket, text: String)
    func TCPSocketDidReceiveData(socket: TCPSocket, data: NSData)
}

public class TCPSocket : NSObject, NSStreamDelegate {
//MARK: - type definition
    public typealias connectedBlock_t = (Void) -> Void
    public typealias disconnectedBlock_t = (NSError?) -> Void
    public typealias receivedTextBlock_t = (String) -> Void
    public typealias receivedDataBlock_t = (NSData) -> Void

    enum CloseCode : UInt16 {
        case Normal                 = 1000
        case GoingAway              = 1001
        case ProtocolError          = 1002
        case ProtocolUnhandledType  = 1003
        // 1004 reserved.
        case NoStatusReceived       = 1005
        //1006 reserved.
        case Encoding               = 1007
        case PolicyViolated         = 1008
        case MessageTooBig          = 1009
    }

    enum InternalErrorCode : UInt16 {
        // 0-999 TCPSocket status codes not used
        case OutputStreamWriteError  = 1
    }
    //MARK: for operation
    //Where the callback is executed. It defaults to the main UI thread queue.
    public var callbackQueue    = dispatch_get_main_queue()

//MARK: config
    let BUFFER_MAX  = 2048

    public weak var delegate: TCPSocketDelegate?
    private var url: NSURL
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    private var isRunLoop = false
    private var connected = false
    private var isCreated = false
    private var outputQueue: NSOperationQueue{ get{
        let ret = NSOperationQueue()
        ret.maxConcurrentOperationCount = 1
        return ret
        }}
    private var inputQueue = Array<NSData>()
    private var fragBuffer: NSData?
    public var headers = Dictionary<String,String>()
    private var connectedBlock: connectedBlock_t? = nil
    private var disconnectedBlock: disconnectedBlock_t? = nil
    private var receivedTextBlock: receivedTextBlock_t? = nil
    private var receivedDataBlock: receivedDataBlock_t? = nil
    public var isConnected :Bool { get{return connected} }

    class func getStreamsToHostWithName(hostname: String, port: Int, inputStream: AutoreleasingUnsafeMutablePointer<NSInputStream?>, outputStream: AutoreleasingUnsafeMutablePointer<NSOutputStream?>){
        // API wrapper
        //NSStream.getStreamsToHostWithName(url.host, port: url.port.integerValue, inputStream: &inputStream, outputStream: &outputStream)
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, hostname, UInt32(port), &readStream, &writeStream)
        inputStream.memory = readStream!.takeUnretainedValue()
        outputStream.memory = writeStream!.takeUnretainedValue()
    }

    // MARK: - Initializer
    //init the TCPSocket with a url
    public init(url: NSURL, delegate:TCPSocketDelegate?=nil) {
        self.url = url
        self.delegate = delegate
        super.init()
    }
    //same as above, just shorter
    public convenience init(url: NSURL, connect:connectedBlock_t?, disconnect:disconnectedBlock_t?=nil, text:receivedTextBlock_t?=nil, data:receivedDataBlock_t?=nil) {
        self.init(url: url)
        connectedBlock = connect
        disconnectedBlock = disconnect
        receivedTextBlock = text
        receivedDataBlock = data
    }

    // MARK: - Connection Interface
    ///Connect to the TCPSocket server on a background thread
    public func open() {
        if isCreated {
            return
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), {
            self.isCreated = true
            self.openSocket()
            self.isCreated = false
        })
    }

    public func close(){
        self.disconnectStream(nil)
    }

// MARK: - Input/Output
    ///write a string to the TCPSocket. This sends it as a text frame.
    public func writeString(str: String) {
        writeData(str.dataUsingEncoding(NSUTF8StringEncoding)!)
    }
    ///write binary data to the TCPSocket. This sends it as a binary frame.
    public func writeData(data: NSData) {
        enqueueOutput(data)
    }

    //private methods below!

    //private method that starts the connection
    private func openSocket() {
        let str: NSString = url.absoluteString!
        var port = url.port ?? 80
        self.initStreams(Int(port))
    }

    //Start the stream connection and write the data to the output stream
    private func initStreams(port: Int) {
        self.dynamicType.getStreamsToHostWithName(url.host!, port: port, inputStream: &inputStream, outputStream: &outputStream)
        inputStream!.delegate = self
        outputStream!.delegate = self

        isRunLoop = true
        inputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        inputStream!.open()
        outputStream!.open()
        while(isRunLoop) {
            NSRunLoop.currentRunLoop().runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture() as! NSDate)
        }
    }

    //MARK: - communication
    //delegate for the stream methods. Processes incoming bytes
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        switch eventCode {
        case NSStreamEvent.HasBytesAvailable:
            if(aStream == inputStream) {
                processInputStream()
            }
        case NSStreamEvent.ErrorOccurred:
            disconnectStream(aStream.streamError)
        case NSStreamEvent.EndEncountered:
            disconnectStream(nil)
        default:
            break
        }
    }
    //disconnect the stream object
    private func disconnectStream(error: NSError?) {
        outputQueue.waitUntilAllOperationsAreFinished()
        let cleanStream:(NSStream?)->Void = {
            if let stream = $0 {
                stream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
                stream.close()
            }
        }
        cleanStream(inputStream)
        inputStream = nil
        cleanStream(outputStream)
        outputStream = nil
        isRunLoop = false
        connected = false
        dispatch_async(callbackQueue,{
            self.disconnectedBlock?(error)
            self.delegate?.TCPSocketDidDisconnect(self, error: error)
        })
    }

    ///handles the incoming bytes and sending them to the proper processing method
    private func processInputStream() {
        var buffer = [UInt8](count: BUFFER_MAX, repeatedValue: 0)
        while(inputStream!.hasBytesAvailable){
            let length = inputStream!.read(buffer, maxLength: BUFFER_MAX)
            if(0<len){
                
            }
        }
        if length > 0 {
            if connected {
                var process = false
                if inputQueue.count == 0 {
                    process = true
                }
                inputQueue.append(NSData(bytes: buffer, length: length))
                if process {
                    dequeueInput()
                }
            } else {
                //                connected = processHTTP(buffer, bufferLen: length)
                //                if !connected {
                //                    dispatch_async(callbackQueue,{
                //                        //self.workaroundMethod()
                //                        self.errorNotificationWithDetail("Invalid HTTP upgrade", 1)
                //                    })
                //                }
            }
        }
    }

    //MARK: - Data Operation
    ///dequeue the incoming input so it is processed in order
    private func dequeueInput() {
        if( 0 < inputQueue.count ){
            let data = inputQueue.removeAtIndex(0)
            /*
            .
            .
            .
            */
            dequeueInput()
        }
    }

    ///used to write things to the stream in a
    private func enqueueOutput(data: NSData) {
        outputQueue.addOperationWithBlock {
        }
    }
}
