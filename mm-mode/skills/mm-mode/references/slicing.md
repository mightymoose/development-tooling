# Slicing

A **slice** is the smallest change that carries its own red-to-green cycle. A worker with no other context builds it from its brief alone and does not make a design choice. The planner makes every decision. The slice worker only writes the bodies.

## Slice rules

- **One behavior, one red test.** A slice adds one behavior that a caller can observe. One new test proves it. The test fails before the slice and passes after it.
- **Smallest that can go red.** Split a slice until a smaller one could not fail a test on its own. If a slice needs two tests that guard different risks, split it.
- **Too small to test means fold it in.** A type, a migration, a config key, a route stub or a helper with no caller cannot go red alone. Fold it into the first slice whose test drives it.
- **Tracer first.** The first slice is the thinnest path through every layer the feature touches, end to end. Each later slice adds one rule, one input case or one error case to that path.
- **Vertical, never horizontal.** A slice never holds only tests, only one layer or only scaffolding.
- **Rejectable alone.** A reviewer can reject one slice and approve its neighbor.
- **Refactor slices are green-to-green.** A slice that only changes structure has no red test. Mark it `refactor`. The checks prove it. Put it before the slice that needs the new shape.
- **Batch the same mechanical edit.** One edit repeated across many files is one slice.
- **Expect one production file and one test file.** A slice that touches more files says why in its brief.
- **Order by dependency.** A slice depends only on slices with lower numbers.

## Slice brief

The planner writes one brief per slice to `<run>/slices/<NN>-<name>.md`. `NN` is a two-digit number that sets the order. The brief is the only input that the slice worker reads, apart from the files it names. Fill every field. Use literal values.

```markdown
# <NN> <name>

Kind: behavior | refactor
Depends on: <slice ids, or none>
Spec: <the spec lines this slice covers, quoted word for word>

## Behavior
<One sentence. What a caller can now do or observe.>

## Files
- Modify `<path>`: <what changes>
- Create `<path>`: <what it holds>
- Test `<path>`

## Interfaces
Consumes: <exact signatures from earlier slices or existing code, with their paths>
Produces: <exact signatures this slice adds or changes>

## Red test
Seam: <the public interface the test drives>
Test name: <in the domain's words>
<The test code, or its setup, action and assertions, with literal expected values from the spec.>
Command: `<command that runs only this test>`
Expected failure: <the error or assertion message before the slice>

## Done
- The test above passes.
- `bash <run>/checks.sh` shows no new failure.

## Out of scope
<Behavior that later slices add. The worker leaves it alone.>
```

For a `refactor` slice, replace "Red test" with "Proof": the existing tests that cover the code, and the command that runs them.

## Plan check

A plan passes when every line below holds. The plan checker writes each line that fails as a finding.

- **Coverage.** Every requirement in the spec maps to at least one slice. Every slice quotes the spec lines it covers.
- **No open decisions.** No brief says "TBD", "handle edge cases", "as needed", "appropriate" or "similar to". No brief names a type, function or file that no slice or existing file defines.
- **One name per thing.** Every symbol has the same name and signature in every brief that names it.
- **Red is real.** Every `behavior` slice has a red test with a literal expected value and an expected failure. The expected value comes from the spec, not from the code.
- **Size.** No slice breaks a slice rule above. No slice could split into two slices that each go red alone.
- **Order.** Each slice depends only on lower numbers. Every signature in "Consumes" exists in the code or in an earlier "Produces".
- **Shared files.** If two slices change the same file, the later slice's brief describes the file as the earlier slice leaves it.
- **Proportion.** A brief gives decisions, not the whole implementation. A brief that holds the full production code has done the slice's work.
