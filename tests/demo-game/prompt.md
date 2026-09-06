# Task: Asteroid Dodge — a small browser game

Build a small browser game called **Asteroid Dodge** in this directory. Vanilla JavaScript only: no build step, no npm dependencies, no frameworks. The game must open by loading `index.html` in a browser (a plain static file server such as `python3 -m http.server` is fine).

## Structure

- `index.html` — one canvas, a start screen, a game-over overlay.
- `src/*.js` — ES modules.
  - Pure game logic (state creation, state update per frame, collision detection, scoring, difficulty ramp, high score handling) lives in pure modules with **no DOM, no `window`, no `document`, no `localStorage` access**. These modules take plain data in and return plain data out.
  - Rendering, input (keyboard and touch) and browser storage live in separate modules. The high score is persisted through a small storage adapter so the pure logic never touches `localStorage` directly.
- `tests/*.test.js` — unit tests for every pure module, runnable with `node --test tests/*.test.js` (Node's built-in test runner, no extra packages).
- `README.md` — how to run the game and the tests.

## Acceptance criteria

1. A start screen shows the title and "Press Space or tap to start".
2. The player controls a ship at the bottom of the canvas; it moves left and right with the arrow keys or A/D, and by touch (drag or tap on the left or right half).
3. Asteroids fall from the top at random horizontal positions and random sizes.
4. The player has 3 lives. A collision removes one life and gives one second of invulnerability.
5. The score grows by 1 for every asteroid that leaves the bottom of the canvas without hitting the ship.
6. Difficulty grows every 10 seconds of play: asteroid speed and spawn rate increase.
7. The P key pauses and resumes the game; a "Paused" label is visible while paused.
8. At 0 lives the game-over overlay shows the final score and the high score, and "Press R or tap to restart".
9. The high score survives a page reload (stored in `localStorage` through the storage adapter).
10. The game loop runs on `requestAnimationFrame` and uses the real elapsed time between frames, so the speed is the same at 60 fps and 30 fps.
11. The canvas is responsive: it fills the window and keeps working after a resize.
12. The browser console shows no errors or warnings during a full play session (start, play, pause, lose, restart).

## Quality requirements

- Every pure module has unit tests; `node --test tests/*.test.js` passes with zero failures.
- `node --check` passes on every file in `src/`.
- Work is split into work packages; each package ends with a git commit with a short message (the repository is already initialised).
- Keep the code simple and readable. No dead code, no TODO comments left behind.

## How to work

Finish the whole task in one go. Do not ask questions; where something is unclear, pick a reasonable option and note it in `README.md` under "Decisions". When everything above is done and the tests pass, write a short summary of what was built and how it was verified, then stop.
