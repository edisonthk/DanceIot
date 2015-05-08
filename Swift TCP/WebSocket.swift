import Foundation
import CoreFoundation

public protocol WebSocketDelegate: class {
    func WebSocketDidConnect(socket: WebSocket)
    func WebSocketDidDisconnect(socket: WebSocket, error: NSError?)
    func WebSocketDidReceiveMessage(socket: WebSocket, text: String)
    func WebSocketDidReceiveData(socket: WebSocket, data: NSData)
}

public class WebSocket : NSObject, NSStreamDelegate {
    //MARK: - type definition
    public typealias connectedBlock_t = (Void) -> Void
    public typealias disconnectedBlock_t = (NSError?) -> Void
    public typealias receivedTextBlock_t = (String) -> Void
    public typealias receivedDataBlock_t = (NSData) -> Void
    //MARK: - enumerate
    enum OpCode : UInt8 {
        case ContinueFrame = 0x0
        case TextFrame = 0x1
        case BinaryFrame = 0x2
        //3-7 are reserved.
        case ConnectionClose = 0x8
        case Ping = 0x9
        case Pong = 0xA
        //B-F reserved.
    }

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

    var optionalProtocols       : Array<String>? = nil
    //Constant Values.
    let headerWSUpgradeName     = "Upgrade"
    let headerWSUpgradeValue    = "TCPSocket"
    let headerWSHostName        = "Host"
    //    let headerWSHostValue = "\(url.host!):\(port!)"
    let headerWSConnectionName  = "Connection"
    let headerWSConnectionValue = "Upgrade"
    let headerWSProtocolName    = "Sec-TCPSocket-Protocol"
    //    let headerWSProtocolValue = ",".join(protocols)
    let headerWSVersionName     = "Sec-TCPSocket-Version"
    let headerWSVersionValue    = "13"
    let headerWSKeyName         = "Sec-TCPSocket-Key"
    //    let headerWSKeyValue = self.generateTCPSocketKey()
    let headerOriginName        = "Origin"
    //    let headerOriginValue = url.absoluteString!
    let headerWSAcceptName      = "Sec-TCPSocket-Accept"
    //    let headerWSAcceptValue
    //MARK: config
    let BUFFER_MAX              = 2048
    let FinMask: UInt8          = 0x80
    let OpCodeMask: UInt8       = 0x0F
    let RSVMask: UInt8          = 0x70
    let MaskMask: UInt8         = 0x80
    let PayloadLenMask: UInt8   = 0x7F
    let MaxFrameSize: Int       = 32

    class WSResponse {
        var isFin = false
        var code: OpCode = .ContinueFrame
        var bytesLeft = 0
        var frameCount = 0
        var buffer: NSMutableData?
    }

    public weak var delegate: WebSocketDelegate?
    private var url: NSURL
    private var inputStream: NSInputStream?
    private var outputStream: NSOutputStream?
    private var isRunLoop = false
    private var connected = false
    private var isCreated = false
    private var writeQueue: NSOperationQueue?
    private var readStack = Array<WSResponse>()
    private var inputQueue = Array<NSData>()
    private var fragBuffer: NSData?
    public var headers = Dictionary<String,String>()
    public var voipEnabled = false
    public var selfSignedSSL = false
    private var connectedBlock: connectedBlock_t? = nil
    private var disconnectedBlock: disconnectedBlock_t? = nil
    private var receivedTextBlock: receivedTextBlock_t? = nil
    private var receivedDataBlock: receivedDataBlock_t? = nil
    public var isConnected :Bool {
        return connected
    }
    // MARK: - Initializer
    //init the TCPSocket with a url
    public init(url: NSURL, delegate:WebSocketDelegate?=nil) {
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
    //closure based instead of the delegate
    public convenience init(aURL: NSURL, protocols: Array<String>, connect:connectedBlock_t?=nil, disconnect:disconnectedBlock_t?=nil, text:receivedTextBlock_t?=nil, data:receivedDataBlock_t?=nil) {
        self.init(url: aURL,connect: connect,disconnect: disconnect,text: text,data: data)
        optionalProtocols = protocols
    }

    // MARK: - Connection
    ///Connect to the TCPSocket server on a background thread
    public func connect() {
        if isCreated {
            return
        }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0), {
            self.isCreated = true
            self.createHTTPRequest()
            self.isCreated = false
        })
    }

    ///disconnect from the TCPSocket server
    public func disconnect() {
        writeError(CloseCode.Normal.rawValue)
    }
    // MARK: - Input/Output
    ///write a string to the TCPSocket. This sends it as a text frame.
    public func writeString(str: String) {
        dequeueWrite(str.dataUsingEncoding(NSUTF8StringEncoding)!, code: .TextFrame)
    }

    ///write binary data to the TCPSocket. This sends it as a binary frame.
    public func writeData(data: NSData) {
        dequeueWrite(data, code: .BinaryFrame)
    }

    //write a   ping   to the TCPSocket. This sends it as a  control frame.
    //yodel a   sound  to the planet.    This sends it as an astroid. http://youtu.be/Eu5ZJELRiJ8?t=42s
    public func writePing(data: NSData) {
        dequeueWrite(data, code: .Ping)
    }
    //private methods below!

    //private method that starts the connection
    private func createHTTPRequest() {

        let str: NSString = url.absoluteString!
        let urlRequest = CFHTTPMessageCreateRequest(kCFAllocatorDefault, "GET",
            url, kCFHTTPVersion1_1)

        var port = url.port
        if port == nil {
            if url.scheme == "wss" || url.scheme == "https" {
                port = 443
            } else {
                port = 80
            }
        }
        self.addHeader(urlRequest, key: headerWSUpgradeName, val: headerWSUpgradeValue)
        self.addHeader(urlRequest, key: headerWSConnectionName, val: headerWSConnectionValue)
        if let protocols = optionalProtocols {
            self.addHeader(urlRequest, key: headerWSProtocolName, val: ",".join(protocols))
        }
        self.addHeader(urlRequest, key: headerWSVersionName, val: headerWSVersionValue)
        self.addHeader(urlRequest, key: headerWSKeyName, val: self.generateTCPSocketKey())
        self.addHeader(urlRequest, key: headerOriginName, val: url.absoluteString!)
        self.addHeader(urlRequest, key: headerWSHostName, val: "\(url.host!):\(port!)")
        for (key,value) in headers {
            self.addHeader(urlRequest, key: key, val: value)
        }

        let serializedRequest: NSData = CFHTTPMessageCopySerializedMessage(urlRequest.takeUnretainedValue()).takeUnretainedValue()
        self.initStreamsWithData(serializedRequest, Int(port!))
    }

    //MARK: - WebSocket Helper
    //Add a header to the CFHTTPMessage by using the NSString bridges to CFString
    private func addHeader(urlRequest: Unmanaged<CFHTTPMessage>,key: String, val: String) {
        let nsKey: NSString = key
        let nsVal: NSString = val
        CFHTTPMessageSetHeaderFieldValue(urlRequest.takeUnretainedValue(), nsKey, nsVal)
    }

    //generate a TCPSocket key as needed in rfc
    private func generateTCPSocketKey() -> String {
        var key = ""
        let seed = 16
        for (var i = 0; i < seed; i++) {
            let uni = UnicodeScalar(UInt32(97 + arc4random_uniform(25)))
            key += "\(Character(uni))"
        }
        var data = key.dataUsingEncoding(NSUTF8StringEncoding)
        var baseKey = data?.base64EncodedStringWithOptions(NSDataBase64EncodingOptions(0))
        return baseKey!
    }

    class func getStreamsToHostWithName(hostname: String, port: Int, inputStream: AutoreleasingUnsafeMutablePointer<NSInputStream?>, outputStream: AutoreleasingUnsafeMutablePointer<NSOutputStream?>){
        // API wrapper
        //higher level API we will cut over to at some point
        //NSStream.getStreamsToHostWithName(url.host, port: url.port.integerValue, inputStream: &inputStream, outputStream: &outputStream)
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(nil, hostname, UInt32(port), &readStream, &writeStream)
        inputStream.memory = readStream!.takeUnretainedValue()
        outputStream.memory = writeStream!.takeUnretainedValue()
    }
    //Start the stream connection and write the data to the output stream
    private func initStreamsWithData(data: NSData, _ port: Int) {
        TCPSocket.getStreamsToHostWithName(url.host!, port: port, inputStream: &inputStream, outputStream: &outputStream)
        inputStream!.delegate = self
        outputStream!.delegate = self

        if url.scheme == "wss" || url.scheme == "https" {
            inputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
            outputStream!.setProperty(NSStreamSocketSecurityLevelNegotiatedSSL, forKey: NSStreamSocketSecurityLevelKey)
        }
        if self.voipEnabled {
            inputStream!.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
            outputStream!.setProperty(NSStreamNetworkServiceTypeVoIP, forKey: NSStreamNetworkServiceType)
        }
        if self.selfSignedSSL {
            let settings: Dictionary<NSObject, NSObject> = [kCFStreamSSLValidatesCertificateChain: NSNumber(bool:false), kCFStreamSSLPeerName: kCFNull]
            inputStream!.setProperty(settings, forKey: kCFStreamPropertySSLSettings as! String)
            outputStream!.setProperty(settings, forKey: kCFStreamPropertySSLSettings as! String)
        }
        isRunLoop = true
        inputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        outputStream!.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
        inputStream!.open()
        outputStream!.open()
        let bytes = UnsafePointer<UInt8>(data.bytes)
        outputStream!.write(bytes, maxLength: data.length)
        while(isRunLoop) {
            NSRunLoop.currentRunLoop().runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture() as! NSDate)
        }
    }

    //MARK: - communication
    //delegate for the stream methods. Processes incoming bytes
    public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {

        if eventCode == .HasBytesAvailable {
            if(aStream == inputStream) {
                processInputStream()
            }
        } else if eventCode == .ErrorOccurred {
            disconnectStream(aStream.streamError)
        } else if eventCode == .EndEncountered {
            disconnectStream(nil)
        }
    }
    //disconnect the stream object
    private func disconnectStream(error: NSError?) {
        if writeQueue != nil {
            writeQueue!.waitUntilAllOperationsAreFinished()
        }
        let cleanStream:(NSStream?)->Void = {
            if let stream = $0 {
                stream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
                stream.close()
            }
        }
        cleanStream(inputStream)
        cleanStream(outputStream)
        outputStream = nil
        isRunLoop = false
        connected = false
        dispatch_async(callbackQueue,{
            self.disconnectedBlock?(error)
            self.delegate?.WebSocketDidDisconnect(self, error: error)
        })
    }

    ///handles the incoming bytes and sending them to the proper processing method
    private func processInputStream() {
        let buf = NSMutableData(capacity: BUFFER_MAX)
        var buffer = UnsafeMutablePointer<UInt8>(buf!.bytes)
        let length = inputStream!.read(buffer, maxLength: BUFFER_MAX)
        if length > 0 {
            if !connected {
                connected = processHTTP(buffer, bufferLen: length)
                if !connected {
                    dispatch_async(callbackQueue,{
                        //self.workaroundMethod()
                        self.errorNotificationWithDetail("Invalid HTTP upgrade", 1)
                    })
                }
            } else {
                var process = false
                if inputQueue.count == 0 {
                    process = true
                }
                inputQueue.append(NSData(bytes: buffer, length: length))
                if process {
                    dequeueInput()
                }
            }
        }
    }
    ///dequeue the incoming input so it is processed in order
    private func dequeueInput() {
        if inputQueue.count > 0 {
            let data = inputQueue[0]
            var work = data
            if (fragBuffer != nil) {
                var combine = NSMutableData(data: fragBuffer!)
                combine.appendData(data)
                work = combine
                fragBuffer = nil
            }
            let buffer = UnsafePointer<UInt8>(work.bytes)
            processRawMessage(buffer, bufferLen: work.length)
            inputQueue = inputQueue.filter{$0 != data}
            dequeueInput()
        }
    }
    ///Finds the HTTP Packet in the TCP stream, by looking for the CRLF.
    private func processHTTP(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
        let CRLFBytes = [UInt8(ascii: "\r"), UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: "\n")]
        var k = 0
        var totalSize = 0
        for var i = 0; i < bufferLen; i++ {
            if buffer[i] == CRLFBytes[k] {
                k++
                if k == 3 {
                    totalSize = i + 1
                    break
                }
            } else {
                k = 0
            }
        }
        if totalSize > 0 {
            if validateResponse(buffer, bufferLen: totalSize) {
                dispatch_async(callbackQueue,{
                    //self.workaroundMethod()
                    self.connectedBlock?()
                    self.delegate?.WebSocketDidConnect(self)
                })
                totalSize += 1 //skip the last \n
                let restSize = bufferLen - totalSize
                if restSize > 0 {
                    processRawMessage((buffer+totalSize),bufferLen: restSize)
                }
                return true
            }
        }
        return false
    }

    ///validates the HTTP is a 101 as per the RFC spec
    private func validateResponse(buffer: UnsafePointer<UInt8>, bufferLen: Int) -> Bool {
        let response = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, 0).takeRetainedValue()
        CFHTTPMessageAppendBytes(response, buffer, bufferLen)
        if CFHTTPMessageGetResponseStatusCode(response) != 101 {
            return false
        }
        let cfHeaders = CFHTTPMessageCopyAllHeaderFields(response)
        let headers: NSDictionary = cfHeaders.takeRetainedValue()
        let acceptKey = headers[headerWSAcceptName] as! NSString
        if acceptKey.length > 0 {
            return true
        }
        return false
    }

    ///process the TCPSocket data
    private func processRawMessage(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        var response = readStack.last
        if response != nil && bufferLen < 2  {
            fragBuffer = NSData(bytes: buffer, length: bufferLen)
            return
        }
        if response != nil && response!.bytesLeft > 0 {
            let resp = response!
            var len = resp.bytesLeft
            var extra = bufferLen - resp.bytesLeft
            if resp.bytesLeft > bufferLen {
                len = bufferLen
                extra = 0
            }
            resp.bytesLeft -= len
            resp.buffer?.appendData(NSData(bytes: buffer, length: len))
            processResponse(resp)
            var offset = bufferLen - extra
            if extra > 0 {
                processExtra((buffer+offset), bufferLen: extra)
            }
            return
        } else {
            let isFin = (FinMask & buffer[0])
            let receivedOpcode = (OpCodeMask & buffer[0])
            let isMasked = (MaskMask & buffer[1])
            let payloadLen = (PayloadLenMask & buffer[1])
            var offset = 2
            if((isMasked > 0 || (RSVMask & buffer[0]) > 0) && receivedOpcode != OpCode.Pong.rawValue) {
                let errCode = CloseCode.ProtocolError.rawValue
                self.errorNotificationWithDetail("masked and rsv data is not currently supported", errCode)
                return
            }
            let isControlFrame = (receivedOpcode == OpCode.ConnectionClose.rawValue || receivedOpcode == OpCode.Ping.rawValue)
            if !isControlFrame && (receivedOpcode != OpCode.BinaryFrame.rawValue && receivedOpcode != OpCode.ContinueFrame.rawValue &&
                receivedOpcode != OpCode.TextFrame.rawValue && receivedOpcode != OpCode.Pong.rawValue) {
                    let errCode = CloseCode.ProtocolError.rawValue
                    self.errorNotificationWithDetail("unknown opcode: \(receivedOpcode)", errCode)
                    return
            }
            if isControlFrame && isFin == 0 {
                let errCode = CloseCode.ProtocolError.rawValue
                self.errorNotificationWithDetail("control frames can't be fragmented", errCode)
                return
            }
            if receivedOpcode == OpCode.ConnectionClose.rawValue {
                var errCode = CloseCode.Normal.rawValue
                if payloadLen == 1 {
                    errCode = CloseCode.ProtocolError.rawValue
                } else if payloadLen > 1 {
                    var codeBuffer = UnsafePointer<UInt16>((buffer+offset))
                    errCode = codeBuffer[0].bigEndian
                    if errCode < 1000 || (errCode > 1003 && errCode < 1007) || (errCode > 1011 && errCode < 3000) {
                        errCode = CloseCode.ProtocolError.rawValue
                    }
                    offset += 2
                }
                if payloadLen > 2 {
                    let len = Int(payloadLen-2)
                    if len > 0 {
                        let bytes = UnsafePointer<UInt8>((buffer+offset))
                        var str: NSString? = NSString(data: NSData(bytes: bytes, length: len), encoding: NSUTF8StringEncoding)
                        if str == nil {
                            errCode = CloseCode.ProtocolError.rawValue
                        }
                    }
                }
                self.errorNotificationWithDetail("connection closed by server", errCode)
                return
            }
            if isControlFrame && payloadLen > 125 {
                writeError(CloseCode.ProtocolError.rawValue)
                return
            }
            var dataLength = UInt64(payloadLen)
            if dataLength == 127 {
                let bytes = UnsafePointer<UInt64>((buffer+offset))
                dataLength = bytes[0].bigEndian
                offset += sizeof(UInt64)
            } else if dataLength == 126 {
                let bytes = UnsafePointer<UInt16>((buffer+offset))
                dataLength = UInt64(bytes[0].bigEndian)
                offset += sizeof(UInt16)
            }
            var len = dataLength
            if dataLength > UInt64(bufferLen) {
                len = UInt64(bufferLen-offset)
            }
            var data: NSData!
            if len < 0 {
                len = 0
                data = NSData()
            } else {
                data = NSData(bytes: UnsafePointer<UInt8>((buffer+offset)), length: Int(len))
            }
            if receivedOpcode == OpCode.Pong.rawValue {
                let step = Int(offset+numericCast(len))
                let extra = bufferLen-step
                if extra > 0 {
                    processRawMessage((buffer+step), bufferLen: extra)
                }
                return
            }
            var response = readStack.last
            if isControlFrame {
                response = nil //don't append pings
            }
            if isFin == 0 && receivedOpcode == OpCode.ContinueFrame.rawValue && response == nil {
                let errCode = CloseCode.ProtocolError.rawValue
                self.errorNotificationWithDetail("continue frame before a binary or text frame", errCode)
                return
            }
            var isNew = false
            if(response == nil) {
                if receivedOpcode == OpCode.ContinueFrame.rawValue  {
                    let errCode = CloseCode.ProtocolError.rawValue
                    self.errorNotificationWithDetail("first frame can't be a continue frame", errCode)
                    return
                }
                isNew = true
                response = WSResponse()
                response!.code = OpCode(rawValue: receivedOpcode)!
                response!.bytesLeft = Int(dataLength)
                response!.buffer = NSMutableData(data: data)
            } else {
                if receivedOpcode == OpCode.ContinueFrame.rawValue  {
                    response!.bytesLeft = Int(dataLength)
                } else {
                    let errCode = CloseCode.ProtocolError.rawValue
                    self.errorNotificationWithDetail("second and beyond of fragment message must be a continue frame", errCode)
                    return
                }
                response!.buffer!.appendData(data)
            }
            if response != nil {
                response!.bytesLeft -= Int(len)
                response!.frameCount++
                response!.isFin = isFin > 0 ? true : false
                if(isNew) {
                    readStack.append(response!)
                }
                processResponse(response!)
            }

            let step = Int(offset+numericCast(len))
            let extra = bufferLen-step
            if(extra > 0) {
                processExtra((buffer+step), bufferLen: extra)
            }
        }

    }

    ///process the extra of a buffer
    private func processExtra(buffer: UnsafePointer<UInt8>, bufferLen: Int) {
        if bufferLen < 2 {
            fragBuffer = NSData(bytes: buffer, length: bufferLen)
        } else {
            processRawMessage(buffer, bufferLen: bufferLen)
        }
    }

    ///process the finished response of a buffer
    private func processResponse(response: WSResponse) -> Bool {
        if response.isFin && response.bytesLeft <= 0 {
            if response.code == .Ping {
                let data = response.buffer! //local copy so it is perverse for writing
                dequeueWrite(data, code: OpCode.Pong)
            } else if response.code == .TextFrame {
                var str: NSString? = NSString(data: response.buffer!, encoding: NSUTF8StringEncoding)
                if str == nil {
                    writeError(CloseCode.Encoding.rawValue)
                    return false
                }
                dispatch_async(callbackQueue,{
                    self.receivedTextBlock?(str! as! String)
                    self.delegate?.WebSocketDidReceiveMessage(self, text: str! as! String)
                })
            } else if response.code == .BinaryFrame {
                let data = response.buffer! //local copy so it is perverse for writing
                dispatch_async(callbackQueue,{
                    //self.workaroundMethod()
                    self.receivedDataBlock?(data)
                    self.delegate?.WebSocketDidReceiveData(self, data: data)
                })
            }
            readStack.removeLast()
            return true
        }
        return false
    }

    ///Create an error and send callback&delegate
    private func errorNotificationWithDetail(detail: String, _ code: UInt16){
        var details = Dictionary<String,String>()
        details[NSLocalizedDescriptionKey] =  detail
        let error = NSError(domain: "TCPSocket", code: Int(code), userInfo: details)

        dispatch_async(callbackQueue,{
            self.disconnectedBlock?(error)
            self.delegate?.WebSocketDidDisconnect(self, error: error)
        })
        writeError(code)
    }

    ///write a an error to the socket
    private func writeError(code: UInt16) {
        let buf = NSMutableData(capacity: sizeof(UInt16))
        var buffer = UnsafeMutablePointer<UInt16>(buf!.bytes)
        buffer[0] = code.bigEndian
        dequeueWrite(NSData(bytes: buffer, length: sizeof(UInt16)), code: .ConnectionClose)
    }
    ///used to write things to the stream in a
    private func dequeueWrite(data: NSData, code: OpCode) {
        if writeQueue == nil {
            writeQueue = NSOperationQueue()
            writeQueue!.maxConcurrentOperationCount = 1
        }
        writeQueue!.addOperationWithBlock {
            //stream isn't ready, let's wait
            var tries = 0;
            while self.outputStream == nil || !self.connected {
                if(tries < 5) {
                    sleep(1);
                } else {
                    break;
                }
                tries++;
            }
            if !self.connected {
                return
            }
            var offset = 2
            UINT16_MAX
            let bytes = UnsafeMutablePointer<UInt8>(data.bytes)
            let dataLength = data.length
            let frame = NSMutableData(capacity: dataLength + self.MaxFrameSize)
            let buffer = UnsafeMutablePointer<UInt8>(frame!.mutableBytes)
            buffer[0] = self.FinMask | code.rawValue
            if dataLength < 126 {
                buffer[1] = CUnsignedChar(dataLength)
            } else if dataLength <= Int(UInt16.max) {
                buffer[1] = 126
                var sizeBuffer = UnsafeMutablePointer<UInt16>((buffer+offset))
                sizeBuffer[0] = UInt16(dataLength).bigEndian
                offset += sizeof(UInt16)
            } else {
                buffer[1] = 127
                var sizeBuffer = UnsafeMutablePointer<UInt64>((buffer+offset))
                sizeBuffer[0] = UInt64(dataLength).bigEndian
                offset += sizeof(UInt64)
            }
            buffer[1] |= self.MaskMask
            var maskKey = UnsafeMutablePointer<UInt8>(buffer + offset)
            SecRandomCopyBytes(kSecRandomDefault, Int(sizeof(UInt32)), maskKey)
            offset += sizeof(UInt32)

            for (var i = 0; i < dataLength; i++) {
                buffer[offset] = bytes[i] ^ maskKey[i % sizeof(UInt32)]
                offset += 1
            }
            var total = 0
            while true {
                if self.outputStream == nil {
                    break
                }
                let writeBuffer = UnsafePointer<UInt8>(frame!.bytes+total)
                var len = self.outputStream?.write(writeBuffer, maxLength: offset-total)
                if len == nil || len! < 0 {
                    var error: NSError?
                    if let streamError = self.outputStream?.streamError {
                        error = streamError
                    } else {
                        let errCode = InternalErrorCode.OutputStreamWriteError.rawValue
                        self.errorNotificationWithDetail("output stream error during write", errCode)
                    }
                    break
                } else {
                    total += len!
                }
                if total >= offset {
                    break
                }
            }
            
        }
    }
    
}