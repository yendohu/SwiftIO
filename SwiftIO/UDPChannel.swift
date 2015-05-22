//
//  UDPMavlinkReceiver.swift
//  SwiftIO
//
//  Created by Jonathan Wight on 4/22/15.
//  Copyright (c) 2015 schwa.io. All rights reserved.
//

import Foundation
import Darwin

public struct Datagram {
    public let from:Address
    public let timestamp:Timestamp
    public let data:NSData

    public init(from:Address, timestamp:Timestamp = Timestamp(), data:NSData) {
        self.from = from
        self.timestamp = timestamp
        self.data = data
    }
}

// MARK: -

/**
 *  A GCD based UDP listener.
 */
public class UDPChannel {

    enum ErrorCode:Int {
        case unknown = -1
    }

    public var address:Address
    public var readHandler:(Datagram -> Void)? = loggingReadHandler
    public var errorHandler:(NSError -> Void)? = loggingErrorHandler

    private var queue:dispatch_queue_t!
    private var source:dispatch_source_t!
    private var socket:Int32!

    public init(address:Address) {
        self.address = address
    }

    public convenience init(hostname:String, port:Int16, family:ProtocolFamily? = nil) {
        let addresses = Address.addresses(hostname, service:"\(port)", `protocol`: .UDP, family: family)
        self.init(address:addresses[0])
    }

    public func resume() {
        socket = Darwin.socket(PF_INET, SOCK_DGRAM, IPPROTO_UDP)
        if socket < 0 {
            handleError(code:.unknown, description: "TODO")
            return
        }

        var reuseSocketFlag:Int = 1
        let result = Darwin.setsockopt(socket, SOL_SOCKET, SO_REUSEADDR, &reuseSocketFlag, socklen_t(sizeof(Int)))
        if result != 0 {
            cleanup()
            handleError(code:.unknown, description: "TODO")
            return
        }

        queue = dispatch_queue_create("io.schwa.SwiftIO.UDP", DISPATCH_QUEUE_CONCURRENT)
        if queue == nil {
            cleanup()
            handleError(code:.unknown, description: "TODO")
            return
        }

        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, UInt(socket), 0, queue)
        if queue == nil {
            cleanup()
            handleError(code:.unknown, description: "TODO")
            return
        }

        dispatch_source_set_cancel_handler(source) {
            self.cleanup()
        }

        dispatch_source_set_event_handler(source) {
            self.read()
        }

        dispatch_source_set_registration_handler(source) {
            var sockaddr = self.address.addr

            let result = Darwin.bind(self.socket, sockaddr.pointer, socklen_t(sockaddr.length))
            if result != 0 {
                let error = self.makeError(code:.unknown, description: "TODO")
                self.errorHandler?(error)
                self.cancel()
                return
            }
        }

        dispatch_resume(source)
    }

    public func cancel() {
        dispatch_source_cancel(source)
    }

    public func send(data:NSData, address:Address! = nil, writeHandler:((Bool,NSError?) -> Void)? = loggingWriteHandler) {
        dispatch_async(queue) {

            let address:Address = address ?? self.address
            var sockaddr = address.addr
            var result = Darwin.sendto(self.socket, data.bytes, data.length, 0, sockaddr.pointer, socklen_t(sockaddr.length))
            if result == data.length {
                writeHandler?(true, nil)
            }
            else if result < 0 {
                writeHandler?(false, self.makeError(code:.unknown, description: "TODO"))
            }
            if result < data.length {
                writeHandler?(false, self.makeError(code:.unknown, description: "TODO"))
            }
        }
    }

    internal func read() {

        var data:NSMutableData! = NSMutableData(length: 4096)

        let address = Address.with() {
            (addr:UnsafeMutablePointer<sockaddr>, inout addrlen:socklen_t) -> Void in


            let result = Darwin.recvfrom(socket, data.mutableBytes, data.length, 0, addr, &addrlen)
            if result < 0 {
                handleError(code:.unknown, description: "TODO")
                return
            }
            data.length = result
        }

        let datagram = Datagram(from: address, timestamp: Timestamp(), data: data)
        readHandler?(datagram)

    }

    internal func cleanup() {
        if let socket = self.socket {
            Darwin.close(socket)
        }
        self.socket = nil
        self.queue = nil
        self.source = nil
    }

    internal func makeError(code:ErrorCode = .unknown, description:String) -> NSError {
        let userInfo = [ NSLocalizedDescriptionKey: description ]
        let error = NSError(domain: "io.schwa.SwiftIO.Error", code: code.rawValue, userInfo: userInfo)
        return error
    }

    internal func handleError(code:ErrorCode = .unknown, description:String) {
        let error = makeError(code:code, description:description)
        errorHandler?(error)
    }
}

// MARK: -

internal func loggingReadHandler(datagram:Datagram) {
    println("READ")
}

internal func loggingErrorHandler(error:NSError) {
    println("ERROR: \(error)")
}

internal func loggingWriteHandler(success:Bool, error:NSError?) {
    if success {
        println("WRITE")
    }
    else {
        loggingErrorHandler(error!)
    }
}
