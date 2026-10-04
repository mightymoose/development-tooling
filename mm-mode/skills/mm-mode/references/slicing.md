# Slicing

A **slice** is the smallest coherent change that a reviewer can accept on its own, and that is safe to stop after. It carries its own red-to-green cycle. A worker with no other context builds it from its brief alone.

The planner makes every product and interface decision. The slice worker makes only local choices inside the brief. An example is a local name, or a call to an existing helper in a listed file.

## Slice rules

- **One behavior, red first.** A slice adds one behavior that a caller can observe. Its tests fail before the slice and pass after it.
- **Smallest that can go red.** Split a slice until a smaller one could not fail a test on its own, or could not stop safely.
- **Safe to stop after.** No slice leaves the branch less safe or less correct than before it. If one part opens a path and another part guards it, such as access and its permission check, keep both parts in one slice.
- **One test per risk.** A slice holds one test for each distinct risk of its behavior. A slice with two tests gives the reason they cannot ship apart. Otherwise, split it.
- **Too small to test means fold it in.** A type, a migration, a config key, a route stub or a helper with no caller cannot go red alone. Fold it into the first slice whose test drives it.
- **Tracer first.** The first slice is the thinnest path through every layer the feature touches, end to end. Each later slice adds one rule, one input case or one error case to that path.
- **Vertical, never horizontal.** A slice never holds only tests, only one layer or only scaffolding.
- **Refactor slices are green-to-green.** A slice that only changes structure has no red test. Mark it `refactor`. The checks prove it. Put it before the slice that needs the new shape.
- **Batch the same mechanical edit.** One edit repeated across many files is one slice.
- **Expect one production file and one test file.** A slice that touches more files says why in its brief.

## Slice ids and order

A slice id is `s<NN>-<name>`, such as `s03-reject-empty-cart`. `NN` is a two-digit number. The id is also the worker's herdr name, so it matches `[a-z][a-z0-9_-]{0,31}`. The loop builds the `planned` slices in ascending number.

- An id never changes and is never reused.
- A new slice takes the next unused number.
- A re-plan runs only when the human directs it. It can rewrite or drop a slice that is not `done`. To put a new slice before an unfinished one, drop the unfinished one and add its replacement after the new slice.
- A `done` slice is never rewritten. A change to its behavior is a new slice.
- A slice depends only on `done` slices and on lower numbers.

## Slice brief

The planner writes three files per slice in `<run>/slices/`:

- `<id>.md` is the brief. It is the only input that the slice worker reads, apart from the files it names. Fill every field. Use literal values.
- `<id>.files` lists every path in the brief's "Files" section, one per line. The slice gate rejects a change to any other file.
- `<id>.cmd` holds the brief's test command on one line. The slice gate runs it after the commit.

```markdown
# <id>

Kind: behavior | refactor
Depends on: <slice ids, or none>
Covers: <the spec lines this slice covers, quoted word for word>

## Behavior
<One sentence. What a caller can now do or observe.>

## Files
- Modify `<path>`: <what changes>
- Create `<path>`: <what it holds>
- Test `<path>`

## Interfaces
Consumes: <exact signatures from done slices or existing code, with their paths>
Produces: <exact signatures this slice adds or changes>

## Red tests
Seam: <the public interface the tests drive>
<For each test: its name in the domain's words, the risk it guards, and its setup, action and assertions with literal expected values from the spec.>
<If there are two or more tests, the reason they cannot ship apart.>
Command: `<command that runs only these tests>`
Expected failure: <for each test, the error or assertion message before the slice>

## Done
- The command above passes.
- `bash <run>/checks.sh` shows no new failure.

## Out of scope
<Behavior that later slices add. The worker leaves it alone.>
```

For a `refactor` slice, replace "Red tests" with "Proof": the existing tests that cover the code, and the command that runs them.

## Plan check

The plan check has two scopes. The orchestrator names the scope in the checker's brief.

- **full:** the first plan. The proposed slices cover the whole spec.
- **replan:** a re-plan the human directed. The `done` slices in the ledger, plus the proposed slices, cover the whole spec.

A plan passes when every line below holds for the proposed slices. The plan checker writes each line that fails as a finding.

- **Coverage.** Coverage holds for the scope. Every proposed slice quotes the lines it covers.
- **No open decisions.** No brief leaves a product or interface choice open. No brief says "TBD", "handle edge cases", "as needed", "appropriate" or "similar to". No brief names a type, function or file that no slice or existing file defines.
- **One name per thing.** Every symbol has the same name and signature in every brief that names it, and in the done slices.
- **Red is real.** Every `behavior` slice has red tests with literal expected values and expected failures. The expected values come from the spec, not from the code.
- **Size.** No slice breaks a slice rule above. No slice could split into two slices that each go red alone and stop safely.
- **Ids and order.** The ids follow the id rules above. Each slice has its `.files` and `.cmd` files, and they match the brief. Every signature in "Consumes" exists in the code, in a done slice or in a lower-numbered "Produces".
- **Shared files.** If two slices change the same file, the later slice's brief describes the file as the earlier slice leaves it.
- **Proportion.** A brief gives decisions, not the whole implementation. A brief that holds the full production code has done the slice's work.
