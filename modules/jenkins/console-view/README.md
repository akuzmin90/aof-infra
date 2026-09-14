Backend console presentation, scoped to the configured backend job and its three
stand jobs. The console always uses a compact view that hides native Pipeline scaffolding, branch
prefixes and allowlisted routine notices. There is no details toggle.
Unknown messages, errors, raw consoleText and downloadable artifacts are preserved.
A MutationObserver processes progressive output and rechecks spans when appended
text includes an error. Other jobs keep their original view.

This separate PageDecorator plugin installs dynamically without upgrading the
already loaded TaskListenerDecorator or restarting Jenkins. Build `build.sh` in a
disposable directory against the controller's WAR and plugin libraries. The HPI
is persisted by the managed init script. Static JavaScript changes can be applied to the expanded web resource and HPI
without a controller restart. Java changes require normal plugin upgrade handling.

Test the DOM behavior with `NODE_PATH=/path/to/node_modules node test.cjs` (jsdom).
