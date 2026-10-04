---
name: principle-test-first
description: Apply before you change what code does, for a feature or a bug fix. Every behavior change starts red, one vertical slice at a time.
---

# Test first

Every change to behavior starts with a test that fails. The code then changes to make it pass.

**Why:** a test written after the code tends to check what the code does, not what it should do. A test you watched fail has proved it can catch the defect.

**Guidance:**

- **Red, then green.** Write one test for one behavior, and watch it fail for the right reason. Then write the least code that makes it pass, with no extra features for tests you have not written yet. Choose where the test goes per **mm-mode:principle-narrowest-seam**.
- **Vertical slices, not horizontal ones.** Write one test, then its code, then the next test. Each test is a tracer bullet that shows where the next one should go. A batch of tests written up front tests imagined behavior and locks in a test structure before you understand the code.
- **Bugs start as a failing test** that reproduces them.
- **Name tests in the domain's words.** A test name says what the code does for its user, such as "user can check out with a valid cart". If the repo has a `CONTEXT.md` or a glossary, use its terms.
- **Refactor outside the loop.** The loop only goes red, then green. Clean up the structure later, in review, while every test stays green. A pure refactor or a docs change needs no new test. A config change that changes behavior does need one.
