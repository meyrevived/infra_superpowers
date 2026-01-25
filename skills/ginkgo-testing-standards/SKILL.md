---
name: ginkgo-testing-standards
description: Use when writing or reviewing Ginkgo/Gomega tests to apply testing structure, style, and organization standards
---

# Ginkgo Testing Standards

## Overview

Write clear, organized, comprehensive Ginkgo tests following consistent style conventions.

**Core principle:** Tests should read like sentences, be organized by scenario type, and be as compact as possible while remaining thorough.

**REQUIRED BACKGROUND:** You MUST understand superpowers:test-driven-development before using this skill. This skill adds Ginkgo-specific standards on top of TDD fundamentals.

## When to Use

**Always when:**
- Writing Ginkgo/Gomega tests
- Reviewing Ginkgo test code
- Planning test suites

**Reference:** See @testing-cheatsheet.md for comprehensive testing methodology and examples.

## Style Standards

### 1. When() vs Context()

**Always use When() instead of Context()**

<Good>
```go
Describe("User validation", func() {
    When("email is valid", func() {
        It("should accept the user", func() { /* ... */ })
    })
})
```
</Good>

<Bad>
```go
Describe("User validation", func() {
    Context("email is valid", func() {  // Don't use Context()
        It("should accept the user", func() { /* ... */ })
    })
})
```
</Bad>

### 2. Should() vs To()

**Always use Should() and ShouldNot() instead of To() and NotTo()**

<Good>
```go
Expect(result).Should(Equal("expected"))
Expect(err).ShouldNot(HaveOccurred())
```
</Good>

<Bad>
```go
Expect(result).To(Equal("expected"))  // Don't use To()
Expect(err).NotTo(HaveOccurred())     // Don't use NotTo()
```
</Bad>

### 3. Sentence Coherence

**The text in Describe() → When() → It() should form a coherent, human-sounding sentence**

<Good>
```go
Describe("User registration", func() {
    When("email is empty", func() {
        It("should return validation error", func() { /* ... */ })
    })
})
```
Reads: "User registration when email is empty should return validation error"
</Good>

<Bad>
```go
Describe("Testing user", func() {
    When("bad email", func() {
        It("error", func() { /* ... */ })
    })
})
```
Reads: "Testing user when bad email error" - incoherent
</Bad>

## Test Organization

### 4. Separate When() Blocks by Scenario Type

**Break tests into separate When() blocks:**
- **Happy path** → One When()
- **Sad paths** → Another When()
- **Edge cases/Chaos** → Another When()

<Good>
```go
Describe("CreateUser", func() {
    When("happy path", func() {
        It("should create user with valid data", func() { /* ... */ })
        It("should generate unique ID", func() { /* ... */ })
    })

    When("sad path", func() {
        It("should reject empty email", func() { /* ... */ })
        It("should reject invalid age", func() { /* ... */ })
    })

    When("edge cases", func() {
        It("should handle extremely long names", func() { /* ... */ })
        It("should handle special characters in email", func() { /* ... */ })
    })
})
```
</Good>

### 5. Bug Exposure Tests

**When tests expose a bug, separate them into a different When() block with explanation**

Use GinkgoWriter.Printf to describe what was expected vs actual result.

<Good>
```go
Describe("CalculateDiscount", func() {
    When("bug discovered in percentage calculation", func() {
        BeforeEach(func() {
            GinkgoWriter.Printf("Expected: 10%% discount on $100 = $90\n")
            GinkgoWriter.Printf("Actual: Returned $89 due to rounding error\n")
        })

        It("should calculate discount correctly", func() {
            result := CalculateDiscount(100.0, 0.10)
            Expect(result).Should(Equal(90.0))
        })
    })
})
```
</Good>

## Compact Test Style

### 6. Inline Function Calls in Expect()

**Place the tested function call directly inside Expect() when possible**

Hit as many tests as possible in as few lines as possible.

**Happy path example:**
```go
Expect(ibmp.doesInstanceHaveTaskRun(logr.Discard(), instance, existingTaskRuns)).Should(Equal(expectedResult))
```

**Sad path example:**
```go
Expect(retrieveInstanceIp("vm-with-nil-network", []*models.PVMInstanceNetwork{nil})).Error().Should(MatchError(ContainSubstring("network entry is nil")))
```

**When NOT to inline:**
- Setup is complex
- You need the result for multiple assertions
- Readability suffers

### 7. DescribeTable() for Identical Expect() with Different Inputs

**Replace multiple It() blocks with identical Expect() patterns using DescribeTable()**

<Good>
```go
DescribeTable("Email validation",
    func(email string, shouldBeValid bool) {
        result := ValidateEmail(email)
        Expect(result).Should(Equal(shouldBeValid))
    },
    Entry("valid email", "user@example.com", true),
    Entry("missing @", "userexample.com", false),
    Entry("empty string", "", false),
    Entry("only @", "@", false),
)
```
</Good>

<Bad>
```go
It("validates correct email", func() {
    Expect(ValidateEmail("user@example.com")).Should(Equal(true))
})
It("rejects email without @", func() {
    Expect(ValidateEmail("userexample.com")).Should(Equal(false))
})
It("rejects empty email", func() {
    Expect(ValidateEmail("")).Should(Equal(false))
})
// Repeated pattern - use DescribeTable instead
```
</Bad>

## Testing Focus

### 8. Test Your Logic, Not External Packages

**Test the logic and functionality of YOUR code, not Go built-ins or third-party packages**

<Good>
```go
// Test your custom validation logic
It("should reject users under age 18", func() {
    user := User{Age: 17}
    Expect(ValidateUser(user)).Should(MatchError("must be 18+"))
})
```
</Good>

<Bad>
```go
// Don't test that == works or that net.ParseIP works
It("should compare strings correctly", func() {
    Expect("test" == "test").Should(BeTrue())  // Testing Go itself
})
It("should parse IP address", func() {
    Expect(net.ParseIP("192.168.1.1")).ShouldNot(BeNil())  // Testing stdlib
})
```
</Bad>

**Focus on:**
- Your business logic
- Your error handling
- Your data transformations
- Integration between YOUR components

**Don't test:**
- Language operators (==, !=, etc.)
- Standard library functionality
- Well-tested third-party packages

## Quick Reference

| Standard | Do | Don't |
|----------|-----|-------|
| **Blocks** | When() | Context() |
| **Matchers** | Should(), ShouldNot() | To(), NotTo() |
| **Naming** | Coherent sentences | Fragmented text |
| **Organization** | Separate When() per type | Mix all scenarios |
| **Bug Tests** | Separate When() + GinkgoWriter | Bury in existing tests |
| **Compactness** | Inline in Expect() | Unnecessary variables |
| **Repetition** | DescribeTable() | Multiple identical It() |
| **Focus** | Test your logic | Test Go/stdlib/packages |

## Testing Cheatsheet Reference

For comprehensive testing methodology including:
- Unit, functional, integration, E2E testing
- Edge cases, stress, chaos, mutation testing
- Mocking, benchmarking, table-driven tests
- Go-specific pitfalls and defensive testing

See: @testing-cheatsheet.md

## Integration with TDD

These standards apply DURING the TDD cycle (superpowers:test-driven-development):

1. **RED**: Write failing Ginkgo test using these standards
2. **GREEN**: Write minimal code to pass
3. **REFACTOR**: Clean up test code following these standards

Don't add these standards as an afterthought - write tests this way from the start.
