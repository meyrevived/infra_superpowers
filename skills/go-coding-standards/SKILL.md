---
name: go-coding-standards
description: Use when writing or reviewing Go code to apply coding standards for simplicity, readability, and maintainability
---

# Go Coding Standards

## Overview

Write simple, readable, maintainable Go code. Every line should serve a purpose.

**Core principle:** Code should do one thing well, avoid repetition, and return early.

## When to Use

**Always when:**
- Writing new Go code
- Reviewing Go code
- Refactoring existing Go code

## Standards

### 1. Fewer Lines, Better Readability

Write concise code, but never sacrifice readability for brevity.

<Good>
```go
func isValid(user *User) bool {
    return user != nil && user.Email != ""
}
```
</Good>

<Bad>
```go
func isValid(user *User) bool {
    if user != nil {
        if user.Email != "" {
            return true
        }
    }
    return false
}
```
</Bad>

### 2. Don't Repeat Yourself (DRY)

Abstract repeated code into functions or helpers.

<Good>
```go
func validateUser(user *User) error {
    if err := validateEmail(user.Email); err != nil {
        return err
    }
    if err := validateAge(user.Age); err != nil {
        return err
    }
    return nil
}

func validateEmail(email string) error { /* ... */ }
func validateAge(age int) error { /* ... */ }
```
</Good>

<Bad>
```go
func validateUser(user *User) error {
    if user.Email == "" {
        return errors.New("email required")
    }
    if !strings.Contains(user.Email, "@") {
        return errors.New("invalid email")
    }
    // Same validation logic repeated elsewhere
}
```
</Bad>

### 3. Iteration and Modularization Over Duplication

Break code into small, reusable modules.

<Good>
```go
// Reusable validator
type Validator interface {
    Validate() error
}

func validateAll(validators ...Validator) error {
    for _, v := range validators {
        if err := v.Validate(); err != nil {
            return err
        }
    }
    return nil
}
```
</Good>

### 4. Single Responsibility

Each function does one thing.

<Good>
```go
func createUser(email, name string) (*User, error) {
    return &User{Email: email, Name: name}, nil
}

func saveUser(db *sql.DB, user *User) error {
    _, err := db.Exec("INSERT INTO users...", user.Email, user.Name)
    return err
}
```
</Good>

<Bad>
```go
func createAndSaveUser(db *sql.DB, email, name string) (*User, error) {
    user := &User{Email: email, Name: name}
    _, err := db.Exec("INSERT INTO users...", user.Email, user.Name)
    return user, err
}
```
Multiple responsibilities: creation AND persistence
</Bad>

### 5. Return Early Pattern

Avoid nested if/else. Return early on error conditions.

<Good>
```go
func processUser(user *User) error {
    if user == nil {
        return errors.New("user is nil")
    }
    if user.Email == "" {
        return errors.New("email required")
    }
    if user.Age < 18 {
        return errors.New("must be 18+")
    }

    // Happy path continues here
    return doProcessing(user)
}
```
</Good>

<Bad>
```go
func processUser(user *User) error {
    if user != nil {
        if user.Email != "" {
            if user.Age >= 18 {
                return doProcessing(user)
            } else {
                return errors.New("must be 18+")
            }
        } else {
            return errors.New("email required")
        }
    }
    return errors.New("user is nil")
}
```
Deeply nested, hard to follow
</Bad>

## Quick Reference

| Principle | Do | Don't |
|-----------|-----|-------|
| **Conciseness** | Short, readable functions | Long nested functions |
| **DRY** | Abstract repeated logic | Copy-paste code |
| **Modularity** | Small, reusable pieces | Monolithic functions |
| **Single Responsibility** | One function, one task | God functions |
| **Control Flow** | Return early on errors | Nested if/else pyramids |

## Common Mistakes

### Mistake: Nested if/else Pyramids

**Fix:** Use return early pattern (see #5 above)

### Mistake: Repeating Validation Logic

**Fix:** Extract validators into reusable functions

### Mistake: Functions Doing Too Much

**Fix:** Break into smaller functions, each with single responsibility

### Mistake: Not Abstracting Common Patterns

**Fix:** When you see the same code 3+ times, create a helper

## Better Approach Checklist

When reviewing your code, ask:

- [ ] Can I return early instead of nesting?
- [ ] Am I repeating any logic?
- [ ] Does each function do exactly one thing?
- [ ] Can I extract common patterns into helpers?
- [ ] Is this as simple as it can be while staying readable?

If you answer "no" to any question, refactor before proceeding.

## Integration with TDD

Write tests FIRST (per superpowers:test-driven-development), then write code following these standards.

Well-structured code is easier to test. If your code is hard to test, it's probably violating one of these principles.
