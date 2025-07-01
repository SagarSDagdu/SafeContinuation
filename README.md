# SafeContinuation

A Swift library to safely wrap callback-based APIs into async/await, preventing the dreaded "Swift task continuation misuse" error.

## The Problem

When using `withCheckedThrowingContinuation`, you might encounter a runtime error if the underlying callback-based API calls the completion handler more than once:

```
Fatal error: SWIFT TASK CONTINUATION MISUSE: function tried to resume its continuation more than once
```

This can happen with unreliable APIs or in complex scenarios where the callback is inadvertently triggered multiple times.

## The Solution

`SafeContinuation` is a Swift library designed to safely wrap callback-based APIs into `async/await`, specifically preventing the "Swift task continuation misuse" error. It acts as a protective layer around `CheckedContinuation`, ensuring that no matter how many times the underlying callback is invoked, the continuation is resumed only once.

## How it Works

`SafeContinuation` wraps the `CheckedContinuation` and includes an internal mechanism (a `resumed` flag and a `lock`) to ensure that `resume()` is called only once. Subsequent calls are simply ignored, preventing the runtime crash.

## Usage

Wrap your `withCheckedThrowingContinuation` call with `withSafeCheckedThrowingContinuation`:

```swift
import SafeContinuation

func fetchData() async throws -> String {
    try await withSafeCheckedThrowingContinuation { continuation in
        // Call your legacy API that might call the completion multiple times
        legacyApiWithCallback {
            continuation.resume(returning: "Data")
        }
    }
}
```

Now, even if the `legacyApiWithCallback`'s completion handler is called multiple times, the continuation will only be resumed once, and your app will not crash.

### Test Coverage

This library boasts 100% test coverage, ensuring its reliability and robustness.

## The Problem I Faced

As a Swift developer, I've embraced modern concurrency with `async/await`. It simplifies asynchronous code significantly. However, when integrating with older, callback-based libraries, especially closed-source ones, I often found myself wrapping their completion handlers using `CheckedContinuation`.

Everything seemed fine during development and testing. But then, after deploying to production, Crashlytics started reporting a dreaded error: `Fatal error: SWIFT TASK CONTINUATION MISUSE: function tried to resume its continuation more than once`. This was puzzling because my code was only calling `resume()` once. The culprit, it turned out, was the third-party library, which, under certain circumstances, was calling its completion handler multiple times.

Since I couldn't modify the closed-source library, I needed a robust solution that would prevent these crashes without altering the library's behavior. This led to the creation of `SafeContinuation`.
