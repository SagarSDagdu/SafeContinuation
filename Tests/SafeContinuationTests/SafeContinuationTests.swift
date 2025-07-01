
import XCTest
@testable import SafeContinuation
import Foundation

final class SafeContinuationTests: XCTestCase {
    
    // MARK: - Basic Functionality Tests
    
    func testBasicResumeWithValue() async {
        let result = await withSafeCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: "success")
            }
        }
        XCTAssertEqual(result, "success")
    }
    
    
    func testBasicDoubleResumeWithValue() async {
        let result = await withSafeCheckedContinuation { continuation in
            DispatchQueue.global().async {
                _ = continuation.resume(returning: "first")
                _ = continuation.resume(returning: "second") // Should be ignored
            }
        }
        XCTAssertEqual(result, "first")
    }
    
    func testBasicResumeWithError() async {
        do {
            try await withSafeCheckedThrowingContinuation(
                of: Void.self,
            ) { continuation in
                DispatchQueue.global().async {
                    continuation.resume(throwing: TestError.testCase)
                }
            }
            XCTFail("Should have thrown an error")
        } catch TestError.testCase {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testResumeWithResultWithFailureCase() async {
        do {
            let _ = try await withSafeCheckedThrowingContinuation(
                of: Result<String, TestError>.self) { continuation in
                    continuation.resume(throwing: TestError.testCase)
                }
            XCTFail("Should have thrown an error")
        } catch TestError.testCase {
            
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testResumeWithResultAfterError() async {
        do {
            let _ = try await withSafeCheckedThrowingContinuation(
                of: Result<String, TestError>.self) { continuation in
                    DispatchQueue.global().async {
                        _ = continuation.resume(throwing: TestError.testCase)
                        _ = continuation.resume(returning: .success("success")) // Should be ignored
                    }
                }
            XCTFail("Should have thrown an error")
        } catch TestError.testCase {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testBasicResumeWithErrorAfterValue() async throws {
        do {
            let value = try await withSafeCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    _ = continuation.resume(returning: "value")
                    _ = continuation.resume(throwing: TestError.testCase) // Should be ignored
                }
            }
            XCTAssertEqual(value, "value")
        } catch TestError.testCase {
            XCTFail("Should not have thrown an error")
        }
    }
        
    func testHighConcurrencyMultipleResumes() async throws {
        let concurrentTasks = 100
        let resultsActor = ResultsActor()
        
        let result = try await withSafeCheckedThrowingContinuation { continuation in
            // Launch many concurrent resume attempts
            for i in 0..<concurrentTasks {
                DispatchQueue.global().async {
                    let success = continuation.resume(returning: "result_\(i)")
                    Task {
                        await resultsActor.append(success)
                    }
                }
            }
        }
        
        // The result should be one of the attempted values
        XCTAssertTrue(result.hasPrefix("result_"))
        
        // Wait for all async operations to complete
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        let results = await resultsActor.getResults()
        
        XCTAssertEqual(results.count, concurrentTasks)
        XCTAssertEqual(results.filter { $0 }.count, 1) // Exactly one should succeed
        XCTAssertEqual(results.filter { !$0 }.count, concurrentTasks - 1) // Rest should fail
    }
    
    func testRaceConditionDeterministicBehavior() async throws {
        // Test that introduces controlled delays to ensure both paths can win
        let iterations = 20
        var successCount = 0
        var errorCount = 0
        
        for i in 0..<iterations {
            do {
                let result = try await withSafeCheckedThrowingContinuation { continuation in
                    let successDelay = Double(i % 2) * 0.001 // Alternate who gets delayed
                    let errorDelay = Double((i + 1) % 2) * 0.001
                    
                    DispatchQueue.global().asyncAfter(deadline: .now() + successDelay) {
                        continuation.resume(returning: "success")
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + errorDelay) {
                        continuation.resume(throwing: TestError.testCase)
                    }
                }
                
                if result == "success" {
                    successCount += 1
                }
            } catch TestError.testCase {
                errorCount += 1
            }
        }
        
        XCTAssertEqual(successCount + errorCount, iterations)
        // With alternating delays, we should see both outcomes
        XCTAssertGreaterThan(successCount, 0)
        XCTAssertGreaterThan(errorCount, 0)
    }
    
    func testHasResumedReturnsTrueAfterResume() async {
        let result = await withSafeCheckedContinuation(
            of: String
                .self) { continuation in
            XCTAssertFalse(continuation.hasResumed)
            continuation.resume(returning: "test")
            XCTAssertTrue(continuation.hasResumed)
        }
        
        XCTAssertEqual(result, "test")
    }
    
    func testResultWithSuccess() async throws {
        let result = try await withSafeCheckedThrowingContinuation{ continuation in
            DispatchQueue.global().async {
                continuation.resume(with: .success("success"))
            }
        }
        
        XCTAssertEqual(result, "success")
    }
    
    func testResultWithFailure() async throws {
        do {
            try await withSafeCheckedThrowingContinuation(
                of: String.self
            ) { continuation in
                DispatchQueue.global().async {
                    continuation.resume(with: .failure(TestError.testCase))
                }
            }
            XCTFail("Should have thrown an error")
        } catch TestError.testCase {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    func testResultWithSuccessAfterFailure() async throws {
        do {
            let _ = try await withSafeCheckedThrowingContinuation(
                of: String.self
            ) { continuation in
                DispatchQueue.global().async {
                    continuation.resume(with: .failure(TestError.testCase))
                    continuation.resume(with: .success("success"))
                }
            }
            XCTFail("Should have thrown an error")
        } catch TestError.testCase {
            // Expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

// MARK: - Helper Types

enum TestError: Error, Equatable {
    case testCase
    case anotherCase
}

// Async-safe actors for collecting results
actor ResultsActor {
    private var results: [Bool] = []
    
    func append(_ result: Bool) {
        results.append(result)
    }
    
    func getResults() -> [Bool] {
        return results
    }
}
