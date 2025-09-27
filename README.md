# SwiftTUI

SwiftTUI lets you compose terminal user interfaces in idiomatic Swift.

## Lightweight test app

SwiftTUI ships with a `LightweightTestApp` helper that wires together terminal
state, presenter, input handling, and a simple menu bar renderer. The helper is
designed for quickly exercising the menu and status bars without assembling the
lower-level types yourself.

```swift
import SwiftTUI

@main
struct DemoHarness {
    static func main() {
        let app = LightweightTestApp(
            width: 100,
            height: 28,
            statusText: "Ready to explore SwiftTUI",
            menuItems: [
                MenuBarItem(title: "File", activationKey: "f") {
                    print("File menu activated")
                },
                MenuBarItem(title: "Help", activationKey: "h") {
                    print("Help menu activated")
                }
            ]
        )

        app.run()
    }
}
```

Calling `run()` switches the terminal into the alternate buffer, renders the
menu bar on the first row, and keeps the status bar synchronized with
`TerminalState.statusText`. Update the `statusText` (for example,
`app.state.statusText = "Loading..."`) or mutate `menuBarModel` to see the
display refresh in place. The helper also connects raw terminal input to the
menu model so you can navigate with the configured activation keys.
