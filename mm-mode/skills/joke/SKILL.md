---
name: joke
description: Tells one short joke about a given topic. Use when a mm-mode playbook step asks for a joke, or when the user asks for a joke directly.
---

# Joke

1. Read the topic from the arguments: $ARGUMENTS
2. If there is no topic, use software development.
3. Write one joke about the topic. Keep it to two lines at most: a setup and a punchline.
4. Return only the joke.
