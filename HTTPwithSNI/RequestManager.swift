//
//  RequestManager.swift
//  HTTPwithSNI
//
//  Created by Rafael Costa on 2024-03-29.
//

import Foundation

struct RequestParameters {
    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }
    
    let url: URL
    let method: HTTPMethod
    let resolvedAddress: String
    let body: Data?
    
    init(
        url: URL = URL(string: "https://reqres.in/api/users")!,
        method: HTTPMethod = .post,
        resolvedAddress: String = "172.67.73.173",
        body: Data? = "{name: 'Rafael'}".data(using: .utf8)
    ) {
        self.url = url
        self.method = method
        self.resolvedAddress = resolvedAddress
        self.body = body
    }
    
    func originalHost() -> String {
        return url.host!
    }
    
    func modifiedURL() -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = resolvedAddress
        return components!.url!
    }
}

final class RequestExecutor {
    enum RequestError {
        case couldNotAssembleURL
        case couldNotAssembleBody
        case unknownHost
        case couldNotSchedule
        case couldNotOpenSocket
        case httpError(statusCode: Int)
    }
    
    typealias CompletionHandler = (Data?, RequestError?) -> Void
    
    init(
        parameters: RequestParameters,
        completionHandler: @escaping CompletionHandler
    ) {
        self.parameters = parameters
        self.completionHandler = completionHandler
        
    }
    
    private let parameters: RequestParameters
    private let completionHandler: CompletionHandler
    private var readStream: CFReadStream?
    
    func setup() {
        guard let cfUrl = CFURLCreateWithString(
            kCFAllocatorDefault,
            parameters.url.absoluteString as CFString,
            nil
        ) else {
            completionHandler(nil, .couldNotAssembleURL)
            return
        }
        
        let requestMessage = CFHTTPMessageCreateRequest(
            kCFAllocatorDefault,
            parameters.method.rawValue as CFString,
            cfUrl,
            kCFHTTPVersion1_1
        )

//        guard let bodyData = CFStringCreateExternalRepresentation(
//            kCFAllocatorDefault,
//            parameters.body as CFString,
//            kCFStringEncodingASCII,
//            0
//        ) else {
//            return
//        }
        
        let host = parameters.originalHost()
        
        let requestMessageRet = requestMessage.takeRetainedValue()

        CFHTTPMessageSetHeaderFieldValue(requestMessageRet, "Host" as CFString, host as CFString)
        
        if let data = parameters.body {
            CFHTTPMessageSetBody(requestMessageRet, data as CFData);
        }
        
        let readStream = CFReadStreamCreateForHTTPRequest(
            kCFAllocatorDefault, requestMessageRet
        )
        
        let readStreamRet = readStream.takeRetainedValue()
        self.readStream = readStreamRet
        
        let securitySettings = [
            String(kCFStreamSSLPeerName): host
        ] as CFDictionary
        
        let setProperty = CFReadStreamSetProperty(
            readStreamRet,
            CFStreamPropertyKey(kCFStreamPropertySSLSettings),
            securitySettings
        )
        
        guard setProperty else {
            completionHandler(nil, .couldNotSchedule)
            return
        }
                
        let unretainedSelf = Unmanaged<RequestExecutor>.passUnretained(self).toOpaque()
        var ctx = CFStreamClientContext(version: 0, info: unretainedSelf, retain: nil, release: nil, copyDescription: nil)
        
        let flags = (CFStreamEventType.hasBytesAvailable.rawValue | CFStreamEventType.errorOccurred.rawValue | CFStreamEventType.endEncountered.rawValue)
        
        let setClient = CFReadStreamSetClient(
            readStreamRet,
            .init(bitPattern: Int(flags)),
            { readStream, event, ctx in
                RequestExecutor.callback(readStream: readStream)
            },
            &ctx
        )
        
        guard setClient else {
            completionHandler(nil, .couldNotSchedule)
            return
        }
        
        CFReadStreamScheduleWithRunLoop(readStreamRet, CFRunLoopGetMain(), .commonModes)
        
        guard CFReadStreamOpen(readStreamRet) else {
            completionHandler(nil, .couldNotOpenSocket)
            return
        }
    }
    
    static func callback(readStream: CFReadStream?) {
        guard let readStream else { return }
        let responseBytes = CFDataCreateMutable(kCFAllocatorDefault, 0);
        var numberOfBytesRead: CFIndex = 0
        
        repeat {
            var buffer = [UInt8].init(repeating: 0, count: 1024)
            let pointer = buffer.withUnsafeMutableBufferPointer { pointer in
                return pointer.baseAddress
            }
            numberOfBytesRead = CFReadStreamRead(readStream, pointer, buffer.count)
            if (numberOfBytesRead > 0)
            {
                CFDataAppendBytes(responseBytes, pointer, numberOfBytesRead);
            }
        } while numberOfBytesRead > 0
                    
                    guard let responseRef = CFReadStreamCopyProperty(readStream, CFStreamPropertyKey(kCFStreamPropertyHTTPResponseHeader)) else {
            return
        }
        
        let response = responseRef as! CFHTTPMessage
        if let responseBytes, !(responseBytes as Data).isEmpty {
            CFHTTPMessageSetBody(response, responseBytes);
        }
        
        var statusCode = CFHTTPMessageGetResponseStatusCode(response)
        
        if statusCode >= 400 {
            // Error!
            
        }
        
        //close and cleanup
        CFReadStreamClose(readStream);
        CFReadStreamUnscheduleFromRunLoop(readStream, CFRunLoopGetCurrent(), .commonModes);
        
        let responseBodyData = CFHTTPMessageCopyBody(response)
        guard let data = responseBodyData?.takeUnretainedValue() else {
            return
        }
        
        let dataSwift = data as Data
        print("Response:", String(data: dataSwift, encoding: .utf8)!)
    }
}

final class RequestManager {
    
}
