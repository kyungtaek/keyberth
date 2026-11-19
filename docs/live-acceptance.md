# Phase 1 live acceptance (not run)

No safe isolated runnable T3 host was identified during the original prototype: installed T3 Code (Beta) 0.1.7 is not an isolated test profile; the project contains source/URL fixtures only. Do not launch deep links into the installed profile to test.

1. Verify a separate T3 0.1.7 test profile and approved local authentication, with no real sessions, and an exact verified USB device plus current firmware. Do not install, flash, or change global settings for this check.
2. Create two synthetic sessions with the same visible name in distinct exact environment/thread identities. Assign distinct slots. From another app, one physical press must foreground the exact target T3 window and navigate to that exact session, no select/pin/open or chooser step. Repeat for both slots with T3 warm and cold; observe process/window state and selected identity rather than just URL dispatch.
3. Refresh status and reorder/swap the synthetic source list; a visible active slot keeps its exact binding even if its color changes. Never arm a changed binding based solely on receipt time. With no proven render acknowledgment, freeze live bindings per attachment and invalidate disabled/removed slots. Simulate a queued/replayed press, disconnect, stale session and timeout; never open the new slot occupant.
4. Only after isolated warm/cold checks and actual USB availability, complete end-to-end HID/LED-to-session test with visual evidence and exact navigation confirmed. Offline fixtures only verify URI shape, identity, and rejection of stale revisions; they do not verify desktop focus, device render, or real key routing.

Future, outside phase 1: key 12 hold-to-dictate requires distinct press and release from actual hardware, safe cancellation on lost release or disconnect, and separate explicit approval/verification. Do not infer it from a normal single press.
