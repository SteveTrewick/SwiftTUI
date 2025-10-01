# Message Box Button Visibility Debug Plan

## Goal
Understand why message box overlays sometimes render fewer buttons than expected (e.g., only one button when three are configured) and identify the precise conditions that suppress the additional buttons.

## Investigation Steps
1. **Reproduce the Issue Reliably**
   - Run the provided menu construction snippet inside the minimal demo app or unit test harness.
   - Force the terminal/view width to the reported failing size (e.g., via `FixedSizeSurface` or mocked `winsize`).
   - Capture the rendered buffer output for the failing width to confirm which strings appear.

2. **Trace Button Layout Inputs**
   - Inspect `MessageBoxOverlay.render(in:)` inputs:
     - `interiorWidth`
     - `buttonRow.buttonWidths`
     - `minimumRowWidth`
   - Add temporary logs at the top of `render` to dump these values along with the computed `spacing`.
   - Verify the row actually executes (guard not returning) by logging immediately before and after the guard.

3. **Validate Width Calculations**
   - Step through calculations:
     - Sum of `buttonWidths` (include surrounding brackets or padding?).
     - Number of gaps = `buttonWidths.count - 1`.
     - `availableGap = interiorWidth - minimumButtonWidths`.
   - Compare expected values against the failing run to see if `availableGap` is negative.

4. **Follow Rendering Loop**
   - Log each iteration of the button placement loop:
     - The `column` before placement.
     - The label being written.
     - The final cursor position after the label.
   - Ensure the row writer is actually invoked for every button (no early `return` inside the loop).

5. **Check Downstream Consumers**
   - If the overlay emits the correct sequences, but the menu still shows one button, capture the final `Surface` buffer or terminal output to confirm whether truncation happens later in the pipeline.
   - Trace through any clipping or viewport logic (`Surface.sized(width:height:)`, `ViewBuffer.applyOverlay`).

6. **Regression Tests**
   - Create a unit test that fixes the viewport width to the failing case and asserts that all three button labels (`[ YOK ]`, `[ NOK ]`, `[ WTF ]`) are present.
   - Add comments explaining the reasoning behind the expected width thresholds.

## Logging / Test Strategy
- Use `log.debug` or temporary `print` guarded with `#if DEBUG` so the output can be enabled without polluting production logs.
- Collect log output alongside the rendered buffer for cross-reference.
- Once the root cause is identified, remove temporary logging and replace it with a focused diagnostic if necessary (e.g., logging when buttons are intentionally skipped).

## Decision Points & Notes
- If calculations show the guard never triggers, investigate whether button rendering stops because the writer exits early (e.g., due to zero width columns or clipping).
- Determine whether `minimumInteriorWidth(for:)` still enforces spacing that exceeds `interiorWidth`.
- Evaluate whether `ButtonRow` remeasurement recalculates widths with brackets or content trimming.
- Decide whether to adjust `spacing` calculation or the minimum width to prioritize buttons over body text.
- Document any assumptions about terminal fonts (monospace) and character widths to rule out multi-width glyph issues.

