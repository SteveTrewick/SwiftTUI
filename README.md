# SwiftTUI

SwiftTUI lets you compose terminal user interfaces in idiomatic Swift.

## Menu Bar Example

The snippet below demonstrates how you can set up a simple menu bar with a
couple of actions and a status bar message.

```swift
import SwiftTUI

@main
struct DemoApp {
    static func main() {
        let app = Application {
            MenuBar {
                Menu("File") {
                    Action("New Window") {
                        print("Create a new window")
                    }
                    Action("Close Window") {
                        print("Close the current window")
                    }
                }

                Menu("Help") {
                    Action("About SwiftTUI") {
                        print("Show about dialog")
                    }
                }
            }

            StatusBar(text: "ncurses can suck it - In the BAYOU. OUTLAW COUNTRY!")
        }

        app.run()
    }
}
```

The `MenuBar` composes menus and actions, and the `StatusBar` ensures the
message "ncurses can suck it - In the BAYOU. OUTLAW COUNTRY!" is always visible
at the bottom of the terminal.
