# TODO

## Menu Enhancement Roadmap

### Immediate Next Step
1. Establish the runtime services that `MenuAction` needs so actions can do more than log text.
   * Introduce an `OverlayManager` protocol and a basic overlay type (for example, a message box) that conforms to the existing `Renderable` pipeline.
   * Expand `AppContext` so actions can request overlay presentation and issue output updates without owning terminal objects themselves.
   * Update `TerminalApp` to assemble the context on demand—right before dispatching an action—so every invocation observes the latest window size, overlay stack, and output controller state.

### Follow-Up Tasks
* Flesh out `MenuAction` factories (e.g. `.message(_:)`, `.noop`, `.openURL(_:)`) using the richer context so simple menus can be wired without bespoke closures.
* Allow accelerators to be configured independently of the item title so duplicate starting letters remain accessible.
* Design a documentation payload (`MenuActionDocumentation`) and surface it through menu items to enable contextual help panes once overlays exist.
* Consider serialization or inspection hooks for the menu hierarchy so external tools can introspect available commands.
