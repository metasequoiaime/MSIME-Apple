import Foundation
import SwiftRs

// Xcode 27 internalizes the same C entry points in SwiftRs' embedded optimized object.
// These ABI-identical public wrappers keep Rust's existing bridge names resolvable.
@_cdecl("retain_object")
public func msimeRetainObject(pointer: UnsafeMutableRawPointer) {
  _ = Unmanaged<AnyObject>.fromOpaque(pointer).retain()
}

@_cdecl("release_object")
public func msimeReleaseObject(pointer: UnsafeMutableRawPointer) {
  Unmanaged<AnyObject>.fromOpaque(pointer).release()
}

@_cdecl("data_from_bytes")
public func msimeDataFromBytes(data: UnsafePointer<UInt8>, size: Int) -> SRData {
  SRData(Array(UnsafeBufferPointer(start: data, count: size)))
}

@_cdecl("string_from_bytes")
public func msimeStringFromBytes(data: UnsafePointer<UInt8>, size: Int) -> SRString {
  SRString(String(decoding: UnsafeBufferPointer(start: data, count: size), as: UTF8.self))
}
