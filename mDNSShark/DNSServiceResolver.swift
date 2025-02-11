import Foundation
import os

// MARK: - Typealias for the Completion Closure
public typealias DNSResolveCompletion = (String?, UInt16?) -> Void

// Create a logger for DNSServiceResolver.
private let dnsLogger = Logger(subsystem: "com.example.ScanX", category: "DNSServiceResolver")

// Define our callback type exactly as expected by the system.
// (Although the imported signature marks the callback parameter as optional,
//  in practice the API requires you to supply a callback, but its parameter is optional.)
public typealias MyDNSServiceResolveReply = @convention(c) (
    DNSServiceRef?,           // service reference
    DNSServiceFlags,          // flags
    UInt32,                   // interface index
    DNSServiceErrorType,      // error code
    UnsafePointer<CChar>?,    // fullname
    UnsafePointer<CChar>?,    // hosttarget
    UInt16,                   // port
    UInt16,                   // txtLen
    UnsafePointer<UInt8>?,    // txtRecord
    UnsafeMutableRawPointer?  // context
) -> Void

// Define the callback. (It must have the non‑optional signature.)
private let dnsServiceResolveCallback: MyDNSServiceResolveReply = { sdRef, flags, interfaceIndex, errorCode, fullname, hosttarget, port, txtLen, txtRecord, context in
    if let context = context {
        // Retrieve the Swift closure from the context pointer.
        let completion = Unmanaged<AnyObject>.fromOpaque(context).takeRetainedValue() as? DNSResolveCompletion
        if let completion = completion {
            if errorCode == kDNSServiceErr_NoError, let hosttarget = hosttarget {
                // DNSService returns the port in network byte order.
                let portValue = UInt16(port.bigEndian)
                let host = String(cString: hosttarget)
                completion(host, portValue)
            } else {
                dnsLogger.error("DNSServiceResolve callback error: \(errorCode, privacy: .public)")
                completion(nil, nil)
            }
        }
    }
}

// MARK: - Helper Function for DNSServiceResolve
private func callDNSServiceResolve(serviceRef: inout DNSServiceRef?,
                                   namePtr: UnsafePointer<CChar>,
                                   typePtr: UnsafePointer<CChar>,
                                   domainPtr: UnsafePointer<CChar>,
                                   context: UnsafeMutableRawPointer?) -> DNSServiceErrorType {
    // Define a typealias that exactly matches the expected signature.
    // Note: The first parameter is an optional pointer to DNSServiceRef?,
    // both flags and interface index are UInt32,
    // and the callback parameter is now optional (MyDNSServiceResolveReply?),
    // which matches the imported signature.
    typealias ResolveFunc = @convention(c) (
        UnsafeMutablePointer<DNSServiceRef?>?,  // pointer to DNSServiceRef? (optional)
        UInt32,                                // flags
        UInt32,                                // interface index
        UnsafePointer<CChar>?,                 // name
        UnsafePointer<CChar>?,                 // regtype
        UnsafePointer<CChar>?,                 // domain
        MyDNSServiceResolveReply?,              // callback (optional)
        UnsafeMutableRawPointer?               // context
    ) -> DNSServiceErrorType

    // Assign DNSServiceResolve to a constant of our expected type.
    let functionPtr: ResolveFunc = DNSServiceResolve

    // Explicitly define literal values.
    let tmpFlags: UInt32 = 0
    let tmpInterfaceIndex: UInt32 = 0

    // Allocate temporary memory for the inout serviceRef.
    let ptr = UnsafeMutablePointer<DNSServiceRef?>.allocate(capacity: 1)
    ptr.initialize(to: serviceRef)

    // Now call the function using our explicitly typed constants.
    let error: DNSServiceErrorType = functionPtr(ptr,
                                                  tmpFlags,
                                                  tmpInterfaceIndex,
                                                  namePtr,
                                                  typePtr,
                                                  domainPtr,
                                                  dnsServiceResolveCallback,  // callback passed as non-nil
                                                  context)
    // Update serviceRef from the pointer’s value.
    serviceRef = ptr.pointee

    // Clean up the allocated memory.
    ptr.deinitialize(count: 1)
    ptr.deallocate()

    return error
}

// MARK: - DNSServiceResolver Helper Class
public class DNSServiceResolver {
    /// Attempts to resolve the service using the low‑level DNS‑SD API.
    ///
    /// - Parameters:
    ///   - name: The service name.
    ///   - type: The service type (for example, "_http._tcp").
    ///   - domain: The service domain (usually "local.").
    ///   - completion: A closure called when resolution completes (or fails).
    public static func resolve(name: String, type: String, domain: String, completion: @escaping DNSResolveCompletion) {
        var serviceRef: DNSServiceRef?
        // Wrap the Swift closure in an unmanaged pointer.
        let context = Unmanaged.passRetained(completion as AnyObject).toOpaque()

        // Convert Swift strings to C strings explicitly.
        let result: DNSServiceErrorType = name.withCString { namePtr in
            return type.withCString { typePtr in
                return domain.withCString { domainPtr in
                    return callDNSServiceResolve(serviceRef: &serviceRef,
                                                 namePtr: namePtr,
                                                 typePtr: typePtr,
                                                 domainPtr: domainPtr,
                                                 context: context)
                }
            }
        }

        if result != kDNSServiceErr_NoError {
            dnsLogger.error("DNSServiceResolve error: \(result, privacy: .public) for service \(name, privacy: .public)")
            Unmanaged<AnyObject>.fromOpaque(context).release()
            completion(nil, nil)
            return
        }

        // If a valid DNSServiceRef is returned, integrate it with a DispatchSource to process events.
        if let serviceRef = serviceRef {
            let fd = DNSServiceRefSockFD(serviceRef)
            if fd != -1 {
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global())
                source.setEventHandler {
                    let processResult = DNSServiceProcessResult(serviceRef)
                    if processResult != kDNSServiceErr_NoError {
                        dnsLogger.error("DNSServiceProcessResult error: \(processResult, privacy: .public) for service \(name, privacy: .public)")
                    }
                }
                source.resume()
            } else {
                dnsLogger.error("Failed to get valid file descriptor for DNSServiceRef for service \(name, privacy: .public)")
                completion(nil, nil)
            }
        } else {
            dnsLogger.error("DNSServiceResolve did not return a valid DNSServiceRef for service \(name, privacy: .public)")
            completion(nil, nil)
        }
    }
}

