# Menu Enhancements: Actions, API Access, and Composable UI Layers

## Current Behaviour and Constraints

* `MenuItem` stores only display attributes and answers to accelerator keys; `performAction()` simply logs the item name without providing any extension point for real behaviour.【F:Sources/SwiftTUI/MenuBar.swift†L4-L90】
* `TerminalApp` invokes `performAction()` after resolving the matching menu entry, but it has no way to pass contextual state (output controller, window size, overlay management, etc.) to the action handler.【F:Sources/SwiftTUI/TerminalApp.swift†L19-L110】

These limitations block richer UI affordances such as message boxes or overlays because the action code cannot mutate shared application state or issue rendering commands in a structured way.

## Strategy: Introduce Command Objects for Menu Actions

1. Define a `MenuAction` struct (or protocol) that wraps both executable behaviour and metadata. Suggested properties:
   * `execute(context: MenuActionContext)` – closure called when the item activates.
   * `documentation: MenuActionDocumentation` – reference to API docs, usage hints, or code snippets for help panes.
2. Replace the hard-coded `performAction()` implementation with dependency injection:
   * Add a stored property `action: MenuAction` to `MenuItem` and extend the initializer so callers can supply their own action.
   * Update `TerminalApp` to pass the appropriate `MenuAction` instances when constructing the menu bar.
3. Provide default actions for simple cases to keep ergonomics high, e.g. `MenuItem(name: "About", action: .message("SwiftTUI 1.0"))`. Back this idea with a small catalog of pre-built command objects so integrators can wire up menus without re-implementing boilerplate behaviours.
   * Offer a ```.message(_:)``` helper that emits a transient overlay or modal displaying text, plus pragmatic fallbacks such as ```.noop``` for placeholder slots and ```.openURL(_:)``` for documentation links.
   * Keep the factory surface thin by relying on the same `MenuActionContext` used elsewhere, so custom actions can still interoperate with the shared services.
   * Suggested implementation:

     ```swift
     struct MenuAction {
         let execute: (MenuActionContext) -> Void

         static func message(_ body: String) -> MenuAction {
             MenuAction { context in
                 context.overlayManager.present(.messageBox(body))
             }
         }

         static var noop: MenuAction { MenuAction { _ in } }

         static func openURL(_ url: URL) -> MenuAction {
             MenuAction { context in
                 context.documentationController.presentExternalURL(url)
             }
         }
     }
     ```

     The default cases double as documentation of how to compose richer commands while ensuring teams can ship usable menus before investing in bespoke behaviour.

This pattern decouples the menu layer from application logic while enabling testable, composable behaviours.

## Strategy: Context Objects for UI Capabilities

1. Create a `MenuActionContext` value that exposes the services actions need, such as:
   * A handle to the `OutputController` for sending ANSI sequences.
   * An `OverlayManager` to push/pop message boxes and other transient UI layers.
   * Access to application state (models, selection, etc.).
2. Build the context inside `TerminalApp` just before dispatching the command. This centralizes dependency wiring and allows mocking in tests.
3. Consider using an environment-style pattern so context values can be overridden for subtrees (similar to SwiftUI's `EnvironmentValues`).

With contextual services, menu actions can request overlays or update persistent UI without reaching into global singletons.

## Strategy: Composable Overlay System

1. Define an `Overlay` protocol that refines `Renderable` and adds stacking hints (z-index, dismissal rules).
2. Implement an `OverlayManager` responsible for:
   * Maintaining a stack/queue of overlays.
   * Rendering overlays after base layers during `TerminalApp.render(everything:)`.
   * Handling dismissal triggers (key commands, timers, etc.).
3. Provide concrete overlays such as `MessageBoxOverlay`, `PopoverOverlay`, or `ModalOverlay`. Each overlay can reference the same `MenuActionContext` API to query docs or other resources.

This architecture keeps overlays composable and makes it straightforward to layer transient UI on top of the existing menu/status bars.

## Strategy: API Reference Injection

1. Extend `MenuActionDocumentation` to include:
   * A short summary string for inline hints.
   * Optional detailed Markdown or a URL for a help pane overlay.
   * Code samples that can be rendered in a dedicated view buffer.
2. Allow `MenuItem` (or its associated action) to expose this documentation so the UI can show context-sensitive help—either on hover (if supported) or via a help command (e.g. `Shift+?`).
3. For automation-friendly menus, provide serialization hooks (e.g. export to JSON) so external tooling can introspect available commands and their docs.

## Additional Implementation Notes

* Keep rendering synchronous with the existing `Renderable` pipeline; overlays can be appended to the `elements` array rendered by `OutputController` so long as they know their absolute coordinates.
* Guard against re-entrancy: actions that trigger overlays should enqueue rendering work rather than mutate the UI mid-draw.
* Continue to respect accelerator keys by deriving them from `MenuItem.name`, but allow overriding for cases where multiple items share a letter.

By adopting command objects, contextual dependency injection, and a dedicated overlay manager, SwiftTUI can support custom menu actions and richer UI constructs without losing the clean separation between rendering primitives and application logic.
