//
//  SafeContinuation.swift
//  SafeContinuation
//
//  Created by Sagar Dagdu on 2025/07/01.
//

import Foundation

/// A thread-safe wrapper around `CheckedContinuation` that prevents double resumption.
///
/// This class ensures that an underlying `CheckedContinuation` is resumed only once,
/// even if its `resume(returning:)` or `resume(throwing:)` methods are called multiple times.
/// This is particularly useful when wrapping callback-based APIs that might inadvertently
/// invoke their completion handlers more than once, leading to `SWIFT TASK CONTINUATION MISUSE`
/// runtime errors.
public final class SafeContinuation<T: Sendable, E: Error>: Sendable {
    private let lock = NSLock()
    private let state: MutableState
    
    /// Internal class to hold the mutable state of the SafeContinuation.
    /// This allows SafeContinuation (a final class) to be Sendable while
    /// managing its internal mutable properties safely.
    private final class MutableState: @unchecked Sendable {
        var continuation: CheckedContinuation<T, E>?
        var isResumed = false
        
        init(_ continuation: CheckedContinuation<T, E>) {
            self.continuation = continuation
        }
    }
    
    /// Initializes a new `SafeContinuation` instance.
    /// - Parameter continuation: The `CheckedContinuation` to wrap.
    public init(_ continuation: CheckedContinuation<T, E>) {
        self.state = MutableState(continuation)
    }
    
    /// Resumes the underlying continuation with a value.
    /// If the continuation has already been resumed, this call is ignored.
    /// - Parameter value: The value to resume the continuation with.
    /// - Returns: `true` if the continuation was successfully resumed by this call, `false` if it was already resumed.
    @discardableResult
    public func resume(returning value: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !state.isResumed, let continuation = state.continuation else {
            return false
        }
        
        state.isResumed = true
        state.continuation = nil // Release the continuation to prevent strong reference cycles
        continuation.resume(returning: value)
        return true
    }
    
    /// Resumes the underlying continuation by throwing an error.
    /// If the continuation has already been resumed, this call is ignored.
    /// - Parameter error: The error to resume the continuation with.
    /// - Returns: `true` if the continuation was successfully resumed by this call, `false` if it was already resumed.
    @discardableResult
    public func resume(throwing error: E) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        guard !state.isResumed, let continuation = state.continuation else {
            return false
        }
        
        state.isResumed = true
        state.continuation = nil // Release the continuation to prevent strong reference cycles
        continuation.resume(throwing: error)
        return true
    }
    
    /// Resumes the underlying continuation with a result.
    /// /// If the continuation has already been resumed, this call is ignored.
    /// - Parameter result: The result to resume the continuation with, which can be either a success or failure.
    public func resume(with result: Result<T,E>) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !state.isResumed, let continuation = state.continuation else {
            return
        }
        
        state.isResumed = true
        state.continuation = nil
        continuation.resume(with: result)
    }
    
    /// A Boolean value indicating whether the continuation has already been resumed.
    public var hasResumed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state.isResumed
    }
}

/// Creates a safe throwing continuation that prevents double resumption.
///
/// Use this function to wrap callback-based APIs that might throw errors and
/// could potentially call their completion handlers more than once.
///
/// - Parameters:
///   - type: The type of value the continuation will return. Defaults to `T.self`.
///   - body: A closure that receives the `SafeContinuation` instance. Inside this closure,
///           you should call the legacy API and then call `continuation.resume(returning:)`
///           or `continuation.resume(throwing:)` exactly once.
/// - Returns: The value passed to `resume(returning:)`.
/// - Throws: The error passed to `resume(throwing:)`.
@discardableResult
public func withSafeCheckedThrowingContinuation<T: Sendable>(
    of type: T.Type = T.self,
    _ body: (SafeContinuation<T, Error>) -> Void
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let safeContinuation = SafeContinuation(continuation)
        body(safeContinuation)
    }
}

/// Creates a safe non-throwing continuation that prevents double resumption.
///
/// Use this function to wrap callback-based APIs that do not throw errors and
/// could potentially call their completion handlers more than once.
/// The error type for this continuation is `Never`.
///
/// - Parameters:
///   - type: The type of value the continuation will return. Defaults to `T.self`.
///   - body: A closure that receives the `SafeContinuation` instance. Inside this closure,
///           you should call the legacy API and then call `continuation.resume(returning:)`
///           exactly once.
/// - Returns: The value passed to `resume(returning:)`.
@discardableResult
public func withSafeCheckedContinuation<T: Sendable>(
    of type: T.Type = T.self,
    _ body: (SafeContinuation<T, Never>) -> Void
) async -> T {
    await withCheckedContinuation { continuation in
        let safeContinuation = SafeContinuation(continuation)
        body(safeContinuation)
    }
}
