# Edge-case probes

Each group is a tour through one kind of risk. Pick the probes that fit the change. A probe that cannot apply gets `n/a` and a reason in the report.

## Input

- Empty, only spaces, and a single character.
- The longest value the field allows, and one character more.
- Very long text with no spaces, to check wrapping and truncation.
- Unicode, emoji, right-to-left text and accented names.
- Characters that break code: quotes, `<script>`, `'; --`, `../`, `%00`.
- Numbers at the edges: 0, -1, the maximum, decimals, and a number in a text field.
- Wrong types, such as a string where the API expects a number, or a missing required field.
- Pasted input, input with leading or trailing spaces, and mixed case where the app compares values.

## State

- A brand-new user with no data, to see every empty state.
- A user with a lot of data, to check pagination, sorting and slow lists.
- Reload in the middle of a flow. Use the browser back button after a submit.
- Open a deep link straight to the page, without the usual path to it.
- Do the action twice in a row, such as saving the same record twice.
- Undo or delete, then check that every place that showed the item updates.

## Who

- Logged out, with an expired session, and with a session that expires during the flow.
- A user with the wrong role, or a user who does not own the record. Try the action through the UI and straight through the API.
- Change an ID in the URL or the request to another user's record.

## Timing

- Double-click the submit button, and submit twice fast.
- The same record edited in two tabs or by two users.
- A slow network: throttle it in the browser, or delay the response.
- An action while a previous request is still running.
- Anything that depends on dates: midnight, month end, time zones and daylight saving changes.

## Failure

- Make the server fail on purpose from the outside: stop a dependency such as the database, block a request in the browser, or cut the network. The user must see a clear message and lose no data.
- An outside service that fails or times out, such as payments, email or a webhook.
- Validation errors: each message must name the problem and keep what the user typed.
- Retry after a failure. It must work, and it must not create a duplicate.

## Neighbors

- Run the main path of each feature next to the changed one: on the same page, in the same flow, or using the same data. A change that works can still break the feature next to it.
- Follow every link and button that the change added or moved.
- Check every place that shows the data this change writes, such as lists, details, emails and exports.

## Platform

- A narrow mobile viewport and a wide one. Look for overlap, truncation and controls that move off screen.
- Keyboard only: tab order, visible focus, Enter and Escape.
- Each control has a label a screen reader can read.
- Every browser or device the repo claims to support, if the change touches layout or input.
