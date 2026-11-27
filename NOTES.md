# nov27-flicker notes
sim udid in ~/PaintWork/nov27-flicker-evidence/udid (delete at end). scripts there: run-test.sh <tag> <Class/test>
done: recording shows one clean lift (held->render landed->retired 80ms); simctl video (v1) of 8 strokes shows no dip (sim too fast, VFR 15fps).
built PaintSoftware/Debug/InkContinuityProbe.swift (-uiTestInkProbe; run-loop observer samples a pixel of window layer tree every turn, publishes ink:<strokes>,<dips> on canvas.host) + test InteractionHitchUITests.testNoCommittedFrameBetweenLiftAndBaseLacksTheStroke
next: run it (p1), stage iPad timing (-uiTestSlowVectorRenderMillis/-uiTestSlowWindowDrawMillis), find dip, root-cause, fix, mutate, fast tier, playcheck
