---
name: principle-narrowest-seam
description: Apply when you choose where a test goes, or review a test. Start from the behavior, then test it at the narrowest seam that still holds the whole behavior.
---

# Narrowest seam

Test each behavior at the narrowest seam that still holds all of it. A **seam** is a public interface where a caller drives the code and sees the result, such as a function, a route or a screen.

**Why:** a seam that is too wide makes a test slow and flaky, and a failure does not point to the cause. A seam that is too narrow leaves part of the behavior untested, so the test passes while the feature is broken.

**The key question:** what risk does this test cover that no other test covers? Two tests can check the same outcome and still earn their place, if each guards a different risk at a different seam.

**Guidance:**

- **Start from the behavior.** Decide what a user or caller should observe, then find the narrowest seam that holds it. Do not start from existing test files or from what is easy to call.
- **Use any test tool the repo has**, from unit tests to Playwright. The behavior picks the tool, not habit.
- **End-to-end tests prove the wiring.** Back end tests, front end tests and a typed contract between them usually cover the functionality. An end-to-end test then only needs to show that the pieces are connected. It does not repeat what lower tests already prove.
- **Prefer user journeys** over many small end-to-end tests. One journey through a real task can prove the wiring of many features at once, such as a shared error flash.
- **Drive the code through the seam.** Check what a caller observes. Reading a result back through the same interface, such as `getUser` after `createUser`, is usually enough. If a write bug and a read bug could hide each other, an independent check, such as a database read, is stronger.
- **Mock only at system boundaries:** outside APIs such as payments or email, time, randomness, and sometimes the database or file system. Use the real code for your own modules. To make a boundary easy to fake, pass the dependency in, and give it one function per operation instead of one generic `fetch`.

**Signs of a weak test:**

- **It is coupled to the implementation.** It mocks your own modules, calls private functions, or checks calls that the behavior does not require. It breaks on a refactor that keeps the behavior. When the count or order is the behavior, such as "charge once" or "authorize before you write", checking it is right.
- **It is tautological.** The expected value is computed the same way the code computes it, so the test cannot disagree with the code. Expected values come from an independent source: a known literal, a worked example or the spec. `expect(total(items)).toBe(15)` checks something. `expect(total(items)).toBe(items.reduce(...))` does not.

**Check:** if you break the behavior on its real path, the test fails. If you change the internals and keep the behavior, the test passes.
