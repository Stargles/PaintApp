import XCTest

/// Characterization tests for `Effect.parameters` — KEYFRAMES.md §8 stage 1's descriptor table.
///
/// **These were written against the settings bar, not against the table.** Every literal in
/// `sliderRows` below was transcribed by hand out of `EffectSettingsBar.rows`' 25 `slider(...)`
/// call sites *before* that switch was touched, and landed while it still hard-coded its own
/// ranges and formats. So they are a genuine pin of what the bar did on 2026-08-28 rather than a
/// restatement of the table: after `rows` was rewritten to read `Effect.parameters`, these same
/// assertions passing unchanged is the evidence that the rewrite moved no number.
///
/// **They cannot see `EffectSettingsBar` itself.** `Views/EffectSection.swift` is a SwiftUI file
/// and only the UIKit/CoreGraphics/Combine sources are compiled into this target a second time
/// (see `CanvasManagerTestSupport`'s header), so a fast-tier test can reach `Effect` and not the
/// view that draws it. The pin is therefore on the table the view now reads. What it does not
/// cover — that `rows` looks each parameter up by the right id, and that it still orders and
/// conditions the rows the way it did — is the `EffectSettingsBar` XCUITests' job, and
/// `EffectSettingsBar.sliderParameter` traps on a miss so a wrong id cannot render as a
/// silently-absent row in a debug build.
///
/// See `CanvasManagerTestSupport.swift` for the characterization-vs-specification distinction.
final class EffectParameterCharacterizationTests: XCTestCase {

    // MARK: - Fixtures

    /// **Hand-typed, because `Effect` cannot be `CaseIterable`** — it has associated values. Every
    /// all-effects sweep in this suite is a literal like this one, which is exactly why
    /// `Effect.parameters` is an exhaustive switch with no `default:`: nothing here would notice a
    /// fourteenth effect, so the compiler has to.
    ///
    /// Fourteen entries over thirteen cases. Gaussian and Directional Blur are one case split by
    /// `Blur.isDirectional`, and both are listed so the "same case, same table" claim is exercised
    /// rather than assumed.
    private static let everyMenuEntry: [Effect] = [
        .brightnessContrast(Effect.BrightnessContrast()),
        .levels(Effect.Levels()),
        .curves(Effect.Curves()),
        .hsvShift(Effect.HSVShift()),
        .gradientMap(Effect.GradientMap()),
        .posterize(Effect.Posterize()),
        .blur(Effect.Blur(radius: 8)),
        .blur(Effect.Blur(radius: 12, angleDegrees: 0, isDirectional: true)),
        .sharpen(Effect.Sharpen(radius: 3, amount: 1)),
        .bloom(Effect.Bloom()),
        .sobel(Effect.Sobel()),
        .outline(Effect.Outline(width: 2)),
        .chromaticAberration(Effect.ChromaticAberration(offsetX: 3, offsetY: 0)),
        .noise(Effect.Noise(amount: 0.08)),
    ]

    /// One line per slider row: the four facts a `slider(...)` call site carried — its
    /// accessibility identifier, its label, its range and its format string.
    private func sliderRows(_ effect: Effect) -> [String] {
        effect.parameters.compactMap { parameter in
            guard let range = parameter.uiRange else { return nil }
            return "\(parameter.controlIdentifier ?? "-")|\(parameter.name)"
                + "|\(range.lowerBound)...\(range.upperBound)|\(parameter.format ?? "-")"
        }
    }

    private func ids(_ effect: Effect) -> [String] { effect.parameters.map(\.id) }

    private func parameter(_ id: String, of effect: Effect,
                           file: StaticString = #filePath, line: UInt = #line) -> EffectParameter? {
        let found = effect.parameters.first { $0.id == id }
        XCTAssertNotNil(found, "No parameter \(id) on \(effect.displayName)", file: file, line: line)
        return found
    }

    // MARK: - The pin: every slider the settings bar drew, before the table existed

    func testTheSlidersMatchTheSettingsBarCallSitesTheyReplaced() {
        XCTAssertEqual(sliderRows(.brightnessContrast(Effect.BrightnessContrast())), [
            "brightness|Brightness|0.0...2.0|%.2f",
            "contrast|Contrast|0.0...2.0|%.2f",
        ])

        XCTAssertEqual(sliderRows(.levels(Effect.Levels())), [
            "inputBlack|Input Black|0.0...1.0|%.2f",
            "inputWhite|Input White|0.0...1.0|%.2f",
            "gamma|Gamma|0.1...5.0|%.2f",
            "outputBlack|Output Black|0.0...1.0|%.2f",
            "outputWhite|Output White|0.0...1.0|%.2f",
        ])

        // The Curves panel is a `CurveEditor`, a caption and a Reset button — no slider anywhere.
        XCTAssertEqual(sliderRows(.curves(Effect.Curves())), [])

        XCTAssertEqual(sliderRows(.hsvShift(Effect.HSVShift())), [
            "hue|Hue|-180.0...180.0|%.0f°",
            "saturation|Saturation|0.0...2.0|%.2f",
            "value|Value|0.0...2.0|%.2f",
        ])

        // The stops editor comes first and carries no slider of its own; Mix is the only one.
        XCTAssertEqual(sliderRows(.gradientMap(Effect.GradientMap())), [
            "mix|Mix|0.0...1.0|%.2f",
        ])

        XCTAssertEqual(sliderRows(.chromaticAberration(Effect.ChromaticAberration())), [
            "offsetX|Offset X|-20.0...20.0|%.1f px",
            "offsetY|Offset Y|-20.0...20.0|%.1f px",
        ])

        // Screen Strength is drawn only when a screen is selected; the *address* exists either way,
        // which is why it is here for a `.none` posterize.
        XCTAssertEqual(sliderRows(.posterize(Effect.Posterize())), [
            "levels|Levels|2.0...32.0|%.0f",
            "screenStrength|Screen Strength|0.0...1.0|%.2f",
        ])

        XCTAssertEqual(sliderRows(.noise(Effect.Noise())), [
            "amount|Amount|0.0...0.5|%.3f",
        ])

        // Angle likewise: hidden on a Gaussian blur, addressable on both.
        let gaussianRows = sliderRows(.blur(Effect.Blur(radius: 8)))
        XCTAssertEqual(gaussianRows, [
            "radius|Radius|0.0...64.0|%.1f px",
            "angle|Angle|0.0...360.0|%.0f°",
        ])
        XCTAssertEqual(sliderRows(.blur(Effect.Blur(radius: 12, isDirectional: true))), gaussianRows,
                       "Gaussian and Directional Blur are one case and share one table")

        XCTAssertEqual(sliderRows(.bloom(Effect.Bloom())), [
            "threshold|Threshold|0.0...1.0|%.2f",
            "radius|Radius|0.0...64.0|%.1f px",
            "intensity|Intensity|0.0...4.0|%.2f",
        ])

        XCTAssertEqual(sliderRows(.sobel(Effect.Sobel())), [])

        XCTAssertEqual(sliderRows(.sharpen(Effect.Sharpen())), [
            "radius|Radius|0.0...32.0|%.1f px",
            "amount|Amount|0.0...4.0|%.2f",
        ])

        XCTAssertEqual(sliderRows(.outline(Effect.Outline())), [
            "width|Width|0.0...24.0|%.1f px",
            "threshold|Alpha Threshold|0.0...1.0|%.2f",
        ])
    }

    /// 25 sliders across the whole catalogue — the count of `slider(...)` call sites in
    /// `EffectSettingsBar.rows` on the day the table was written.
    func testThereAreTwentyFiveSlidersInTheWholeCatalogue() {
        let cases = Self.everyMenuEntry.filter {
            // Both blur entries are one case; count it once.
            if case .blur(let blur) = $0 { return !blur.isDirectional }
            return true
        }
        XCTAssertEqual(cases.count, 13, "Thirteen cases behind fourteen menu entries")
        XCTAssertEqual(cases.flatMap { sliderRows($0) }.count, 25)
    }

    /// **Every parameter a keyframe channel can drive carries a format string** — the premise TODO
    /// (38)(d)'s readout rests on, and the reason `TimelineGraphBand.Channel.format` is optional and
    /// yet never nil in practice.
    ///
    /// `isScalarAnimatable` is `.continuous && .double`, which is exactly the `double(…)` factory,
    /// and every one of its call sites passes a format. So a dragged node always prints in the units
    /// its own slider prints in and never falls through to the generic three-significant-figures
    /// answer. The day a `double(…)` arrives with `format: nil` this goes red, which is the day the
    /// band would start reading a number differently from the settings bar.
    func testEveryAnimatableParameterCarriesAFormatForTheGraphEditorToRead() {
        // By id, because `everyMenuEntry` lists Gaussian and Directional Blur separately and they are
        // one case sharing one table — the same dedup `testThereAreTwentyFiveSlidersInTheWholeCatalogue`
        // does by filtering the case, reached from the other side. Ids are unique across the
        // catalogue (`testIdsAreUniqueWithinAndAcrossEffects`), so a set of them is the true count.
        var animatable: Set<String> = []
        for effect in Self.everyMenuEntry {
            for parameter in effect.parameters where parameter.isScalarAnimatable {
                XCTAssertNotNil(parameter.format, "\(parameter.id) animates but prints in no units")
                animatable.insert(parameter.id)
            }
        }
        XCTAssertEqual(animatable.count, 24,
                       "PREMISE: the animatable set — got \(animatable.sorted())")
        XCTAssertFalse(animatable.contains("posterize.levels"), """
            PREMISE: 24 and not 25, and this is the one slider that is not among them — an `Int`             field, so `.stepped` rather than `.continuous`, and no scalar channel drives it. The             graph editor cannot draw a curve for it, so the readout is never asked about it.
            """)
    }

    /// A slider is exactly a parameter with a UI range, and a UI range implies a format string.
    func testAUiRangeAndAFormatArriveTogether() {
        for effect in Self.everyMenuEntry {
            for parameter in effect.parameters {
                XCTAssertEqual(parameter.uiRange == nil, parameter.format == nil,
                               "\(parameter.id) has one of range/format and not the other")
            }
        }
    }

    // MARK: - Coverage of the payload structs

    /// **33 stored fields over 13 payload structs, and every one of them addressable.** The count
    /// is the point: a field added to a payload struct and not to the table is a knob no keyframe
    /// can reach, and nothing else in the app would say so.
    func testEveryStoredFieldOfEveryPayloadHasAnAddress() {
        let expected: [(Effect, Int)] = [
            (.levels(Effect.Levels()), 5),
            (.curves(Effect.Curves()), 1),
            (.brightnessContrast(Effect.BrightnessContrast()), 2),
            (.hsvShift(Effect.HSVShift()), 3),
            (.gradientMap(Effect.GradientMap()), 2),
            (.chromaticAberration(Effect.ChromaticAberration()), 2),
            (.posterize(Effect.Posterize()), 3),
            (.noise(Effect.Noise()), 3),
            (.blur(Effect.Blur()), 3),
            (.bloom(Effect.Bloom()), 4),
            (.sobel(Effect.Sobel()), 0),
            (.sharpen(Effect.Sharpen()), 2),
            (.outline(Effect.Outline()), 3),
        ]
        for (effect, count) in expected {
            XCTAssertEqual(effect.parameters.count, count,
                           "\(effect.displayName) has \(count) stored fields")
            // `Mirror` counts what the struct actually stores, so this fails when a field is added
            // to a payload and not to the table — which is the drift the table exists to prevent.
            XCTAssertEqual(Self.storedFieldCount(effect), count,
                           "\(effect.displayName)'s payload no longer has \(count) stored fields")
        }
        XCTAssertEqual(expected.map(\.1).reduce(0, +), 33)
    }

    private static func storedFieldCount(_ effect: Effect) -> Int {
        switch effect {
        case .levels(let p):              return Mirror(reflecting: p).children.count
        case .curves(let p):              return Mirror(reflecting: p).children.count
        case .brightnessContrast(let p):  return Mirror(reflecting: p).children.count
        case .hsvShift(let p):            return Mirror(reflecting: p).children.count
        case .gradientMap(let p):         return Mirror(reflecting: p).children.count
        case .chromaticAberration(let p): return Mirror(reflecting: p).children.count
        case .posterize(let p):           return Mirror(reflecting: p).children.count
        case .noise(let p):               return Mirror(reflecting: p).children.count
        case .blur(let p):                return Mirror(reflecting: p).children.count
        case .bloom(let p):               return Mirror(reflecting: p).children.count
        case .sobel(let p):               return Mirror(reflecting: p).children.count
        case .sharpen(let p):             return Mirror(reflecting: p).children.count
        case .outline(let p):             return Mirror(reflecting: p).children.count
        }
    }

    /// **Sobel is the zero-parameter effect and the table says so with an empty list**, not with a
    /// missing entry. Anything drawing a channel list has to survive it.
    func testSobelHasNoParameters() {
        XCTAssertEqual(Effect.sobel(Effect.Sobel()).parameters.count, 0)
        XCTAssertEqual(Effect.sobel(Effect.Sobel()).displayName, "Sobel")
    }

    // MARK: - The ids, which are what a saved keyframe track stores

    func testTheIdsAreTheirWholeStableList() {
        // The two blur entries are one case, so the flattened list repeats blur's three; `Set`
        // folds them back together.
        XCTAssertEqual(Set(Self.everyMenuEntry.flatMap { ids($0) }).sorted(), [
            "bloom.input", "bloom.intensity", "bloom.radius", "bloom.threshold",
            "blur.angle", "blur.directional", "blur.radius",
            "brightnessContrast.brightness", "brightnessContrast.contrast",
            "chromaticAberration.offsetX", "chromaticAberration.offsetY",
            "curves.points",
            "gradientMap.mix", "gradientMap.stops",
            "hsvShift.hue", "hsvShift.saturation", "hsvShift.value",
            "levels.gamma", "levels.inputBlack", "levels.inputWhite",
            "levels.outputBlack", "levels.outputWhite",
            "noise.amount", "noise.monochrome", "noise.seed",
            "outline.color", "outline.threshold", "outline.width",
            "posterize.levels", "posterize.screen", "posterize.screenStrength",
            "sharpen.amount", "sharpen.radius",
        ])
    }

    func testIdsAreUniqueWithinAndAcrossEffects() {
        var seen = Set<String>()
        for effect in Self.everyMenuEntry {
            XCTAssertEqual(Set(ids(effect)).count, ids(effect).count,
                           "\(effect.displayName) repeats an id")
            for id in ids(effect) where !seen.contains(id) { seen.insert(id) }
        }
        XCTAssertEqual(seen.count, 33)
    }

    /// **The id is not the field name, deliberately.** Two already differ, and a Swift rename must
    /// never move one — a document on disk carries these strings.
    func testTwoIdsDeliberatelyDoNotMatchTheirFieldNames() {
        XCTAssertEqual(parameter("hsvShift.hue", of: .hsvShift(Effect.HSVShift()))?.keyPath,
                       \Effect.HSVShift.hueDegrees)
        XCTAssertEqual(parameter("blur.angle", of: .blur(Effect.Blur()))?.keyPath,
                       \Effect.Blur.angleDegrees)
    }

    /// The key path is the typed half of the address, and `read`/`write` are built from it — so
    /// naming the wrong field here would be a wrong write, not merely a wrong label.
    func testKeyPathsNameTheFieldTheyClaim() {
        XCTAssertEqual(parameter("blur.radius", of: .blur(Effect.Blur()))?.keyPath,
                       \Effect.Blur.radius)
        XCTAssertEqual(parameter("bloom.intensity", of: .bloom(Effect.Bloom()))?.keyPath,
                       \Effect.Bloom.intensity)
        XCTAssertEqual(parameter("outline.color", of: .outline(Effect.Outline()))?.keyPath,
                       \Effect.Outline.color)
        XCTAssertEqual(parameter("curves.points", of: .curves(Effect.Curves()))?.keyPath,
                       \Effect.Curves.points)
        XCTAssertEqual(parameter("posterize.screen", of: .posterize(Effect.Posterize()))?.keyPath,
                       \Effect.Posterize.screen)
    }

    // MARK: - Animation kinds

    /// **Six structural fields hold, and these are they.** Two of the six change the render *shape*
    /// rather than a number — `blur.directional` rewrites the pass list from two passes to one, and
    /// `bloom.input` decides whether the compositor performs an entire sub-walk into two borrowed
    /// textures — so they could not be tweened even in principle.
    func testTheSixSteppedParametersAreTheStructuralOnes() {
        let stepped = Self.everyMenuEntry
            .flatMap { $0.parameters }
            .filter { $0.animation == .stepped }
            .map(\.id)
        XCTAssertEqual(Set(stepped), [
            "posterize.levels", "posterize.screen",
            "noise.monochrome", "noise.seed",
            "blur.directional", "bloom.input",
        ])
    }

    /// The owner's ruling on KEYFRAMES.md §9 question 4: same count tweens element by element,
    /// different counts hold. Only two parameters carry a variable-length list.
    func testTheTwoVariableLengthParametersAreComponentwise() {
        let componentwise = Self.everyMenuEntry
            .flatMap { $0.parameters }
            .filter { $0.animation == .componentwise }
            .map(\.id)
        XCTAssertEqual(Set(componentwise), ["curves.points", "gradientMap.stops"])
    }

    /// 24 `Double`s plus `Outline.color`, whose four channels tween as one value with a fixed count
    /// — which is why it is continuous rather than componentwise.
    func testTwentyFiveParametersAreContinuous() {
        let continuous = Self.everyMenuEntry
            .filter { if case .blur(let b) = $0 { return !b.isDirectional }; return true }
            .flatMap { $0.parameters }
            .filter { $0.animation == .continuous }
        XCTAssertEqual(continuous.count, 25)
        XCTAssertEqual(continuous.filter { $0.value == .colour }.map(\.id), ["outline.color"])
        XCTAssertEqual(continuous.filter { $0.value == .double }.count, 24)
    }

    /// Nothing is un-animatable today. The case exists so a later parameter that genuinely is
    /// cannot inherit `.stepped` by default.
    func testNothingIsUnanimatableYet() {
        XCTAssertTrue(Self.everyMenuEntry.flatMap { $0.parameters }
            .allSatisfy { $0.animation != .notAnimatable })
    }

    // MARK: - The UI range and the model domain are two different facts

    /// **Every place the slider stops short of what the model accepts.** The blur radii are the
    /// headline — `maxBlurTaps` is 128 and the slider caps at 64 — but the grades clamp nothing at
    /// all, so most of the table's domains are infinite in both directions.
    func testTheModelDomainIsWiderThanTheSliderWhereverTheModelSaysSo() {
        // `tapCount` clamps to `maxBlurTaps`, and three effects reach it.
        for (id, effect, uiTop) in [
            ("blur.radius", Effect.blur(Effect.Blur()), 64.0),
            ("bloom.radius", Effect.bloom(Effect.Bloom()), 64.0),
            ("sharpen.radius", Effect.sharpen(Effect.Sharpen()), 32.0),
        ] {
            let p = parameter(id, of: effect)
            XCTAssertEqual(p?.uiRange?.upperBound, uiTop)
            XCTAssertEqual(p?.modelDomain.upperBound, 128, "\(id) reaches maxBlurTaps")
        }

        // `Sharpen.amount`'s own doc: negative is deliberately reachable, and `amount: -1`
        // reproduces a plain blur byte for byte.
        let amount = parameter("sharpen.amount", of: .sharpen(Effect.Sharpen()))
        XCTAssertEqual(amount?.uiRange, 0...4)
        XCTAssertTrue(amount?.modelDomain.contains(-1) == true,
                      "amount: -1 is the pinned blur identity and must be keyable")

        // `params` floors levels at 2 and imposes no ceiling; the 32 is the slider's alone.
        let levels = parameter("posterize.levels", of: .posterize(Effect.Posterize()))
        XCTAssertEqual(levels?.uiRange, 2...32)
        XCTAssertEqual(levels?.modelDomain.lowerBound, 2)
        XCTAssertEqual(levels?.modelDomain.upperBound, .infinity)

        // `max(intensity, 0)` — floored, never capped.
        let intensity = parameter("bloom.intensity", of: .bloom(Effect.Bloom()))
        XCTAssertEqual(intensity?.uiRange, 0...4)
        XCTAssertEqual(intensity?.modelDomain, 0...(.infinity))

        // Outline is the one parameter where the two agree exactly: the slider's ceiling *is*
        // `maxOutlineRadius`, which is also what `params` clamps to.
        let width = parameter("outline.width", of: .outline(Effect.Outline()))
        XCTAssertEqual(width?.uiRange, 0...Effect.maxOutlineRadius)
        XCTAssertEqual(width?.modelDomain, 0...Effect.maxOutlineRadius)

        // The two that clamp to exactly their slider range.
        XCTAssertEqual(parameter("bloom.threshold", of: .bloom(Effect.Bloom()))?.modelDomain, 0...1)
        XCTAssertEqual(parameter("outline.threshold", of: .outline(Effect.Outline()))?.modelDomain, 0...1)
    }

    /// The grades guard rather than clamp, so a key outside the slider's travel is meaningful for
    /// every one of them.
    func testTheGradesHaveNoModelBoundAtAll() {
        let unbounded = [
            ("levels.inputBlack", Effect.levels(Effect.Levels())),
            ("levels.inputWhite", Effect.levels(Effect.Levels())),
            ("levels.outputBlack", Effect.levels(Effect.Levels())),
            ("levels.outputWhite", Effect.levels(Effect.Levels())),
            ("brightnessContrast.brightness", .brightnessContrast(Effect.BrightnessContrast())),
            ("brightnessContrast.contrast", .brightnessContrast(Effect.BrightnessContrast())),
            ("hsvShift.hue", .hsvShift(Effect.HSVShift())),
            ("hsvShift.saturation", .hsvShift(Effect.HSVShift())),
            ("hsvShift.value", .hsvShift(Effect.HSVShift())),
            ("gradientMap.mix", .gradientMap(Effect.GradientMap())),
            ("chromaticAberration.offsetX", .chromaticAberration(Effect.ChromaticAberration())),
            ("chromaticAberration.offsetY", .chromaticAberration(Effect.ChromaticAberration())),
            ("posterize.screenStrength", .posterize(Effect.Posterize())),
            ("noise.amount", .noise(Effect.Noise())),
            ("blur.angle", .blur(Effect.Blur())),
            ("sharpen.amount", .sharpen(Effect.Sharpen())),
        ]
        for (id, effect) in unbounded {
            XCTAssertEqual(parameter(id, of: effect)?.modelDomain, EffectParameter.unbounded, id)
        }
        // `transfer` skips the power when gamma <= 0, so gamma is the one grade with a floor.
        XCTAssertEqual(parameter("levels.gamma", of: .levels(Effect.Levels()))?.modelDomain,
                       0...(.infinity))
    }

    // MARK: - Quantisation

    /// **The trap a graph editor has to say out loud.** `tapCount` rounds a radius to whole pixels
    /// before either backend sees it, so radius 8.0 and 8.4 render byte-identically and a smoothly
    /// keyframed ramp comes out in integer steps. It is not only the blur's — bloom's and
    /// sharpen's radii reach the same function.
    func testThreeRadiiAreRoundedByTheRenderPath() {
        let rounded = Self.everyMenuEntry
            .flatMap { $0.parameters }
            .filter { $0.quantisation == .roundedByTheRenderPath }
            .map(\.id)
        XCTAssertEqual(Set(rounded), ["blur.radius", "bloom.radius", "sharpen.radius"])

        // The measurement behind the claim: two radii inside one pixel, one pass list.
        XCTAssertEqual(Effect.blur(Effect.Blur(radius: 8.0)).passes,
                       Effect.blur(Effect.Blur(radius: 8.4)).passes)
        XCTAssertNotEqual(Effect.blur(Effect.Blur(radius: 8.0)).passes,
                          Effect.blur(Effect.Blur(radius: 8.6)).passes)

        // Outline sidesteps it — `params` puts the fractional width in `amount`, not in `taps` —
        // and the table records that by leaving it continuous.
        XCTAssertEqual(parameter("outline.width", of: .outline(Effect.Outline()))?.quantisation,
                       .continuous)
        XCTAssertNotEqual(Effect.outline(Effect.Outline(width: 2.0)).params.amount,
                          Effect.outline(Effect.Outline(width: 2.4)).params.amount)
    }

    func testTheIntegralParametersAreTheOnesWhoseFieldIsNotADouble() {
        let integral = Self.everyMenuEntry
            .flatMap { $0.parameters }
            .filter { $0.quantisation == .integral }
            .map(\.id)
        XCTAssertEqual(Set(integral), [
            "posterize.levels", "posterize.screen",
            "noise.monochrome", "noise.seed",
            "blur.directional", "bloom.input",
        ])
    }

    // MARK: - The scalar bridge

    /// Read a value, write a different one, read it back. Covers all 30 scalar parameters, which is
    /// what a keyframe channel actually drives.
    func testEveryScalarParameterRoundTripsThroughReadAndWrite() {
        for effect in Self.everyMenuEntry {
            for parameter in effect.parameters where parameter.read(effect) != nil {
                // A value inside the model domain and distinct from the default.
                let probe: Double
                switch parameter.value {
                case .boolean:         probe = parameter.read(effect) == 0 ? 1 : 0
                case .option:          probe = parameter.modelDomain.upperBound
                case .unsignedInteger: probe = 4242
                case .integer:         probe = 7
                default:               probe = min(max(0.375, parameter.uiRange?.lowerBound ?? 0),
                                                   parameter.uiRange?.upperBound ?? 1)
                }
                let written = parameter.write(effect, probe)
                XCTAssertEqual(parameter.read(written) ?? .nan, probe, accuracy: 1e-9,
                               "\(parameter.id) did not read back what was written")
                // Writing a parameter must never change *which* effect this is. The one entry
                // that legitimately renames itself is `blur.directional`, which is exactly what
                // splits one case across two menu entries.
                XCTAssertTrue(written.displayName == effect.displayName
                              || parameter.id == "blur.directional",
                              "\(parameter.id) changed which effect this is")
            }
        }
    }

    /// A write through the wrong case is the identity, not a crash and not a silent conversion —
    /// the property that lets a channel survive the artist changing the effect out from under it.
    func testWritingThroughTheWrongCaseChangesNothing() {
        let bloom = Effect.bloom(Effect.Bloom())
        let radius = parameter("blur.radius", of: .blur(Effect.Blur()))
        XCTAssertNil(radius?.read(bloom))
        XCTAssertEqual(radius?.write(bloom, 40), bloom)
    }

    /// The three compound values have no single number, so the scalar bridge refuses them rather
    /// than half-addressing one. They need a channel that speaks their own type.
    func testCompoundParametersHaveNoScalarBridge() {
        let compound: [(String, Effect)] = [
            ("curves.points", .curves(Effect.Curves())),
            ("gradientMap.stops", .gradientMap(Effect.GradientMap())),
            ("outline.color", .outline(Effect.Outline())),
        ]
        for (id, effect) in compound {
            let p = parameter(id, of: effect)
            XCTAssertNil(p?.read(effect), "\(id) must not pretend to be a scalar")
            XCTAssertEqual(p?.write(effect, 0.5), effect, "\(id) must not accept a scalar write")
        }
    }

    /// An option addresses every case of its enum by index, in `allCases` order.
    func testTheOptionBridgeReachesEveryCase() {
        let screen = parameter("posterize.screen", of: .posterize(Effect.Posterize()))
        XCTAssertEqual(screen?.modelDomain, 0...2)
        for (index, expected) in Effect.Screen.allCases.enumerated() {
            let written = screen?.write(.posterize(Effect.Posterize()), Double(index))
            guard case .posterize(let p)? = written else { return XCTFail("not a posterize") }
            XCTAssertEqual(p.screen, expected)
        }

        let input = parameter("bloom.input", of: .bloom(Effect.Bloom()))
        XCTAssertEqual(input?.modelDomain, 0...1)
        for (index, expected) in Effect.Input.allCases.enumerated() {
            let written = input?.write(.bloom(Effect.Bloom()), Double(index))
            guard case .bloom(let p)? = written else { return XCTFail("not a bloom") }
            XCTAssertEqual(p.input, expected)
        }
    }

    /// The `Int` bridge rounds the way the settings bar's Levels slider already did.
    func testTheIntegerBridgeRoundsRatherThanTruncates() {
        let levels = parameter("posterize.levels", of: .posterize(Effect.Posterize()))
        guard case .posterize(let p)? = levels?.write(.posterize(Effect.Posterize()), 6.7) else {
            return XCTFail("not a posterize")
        }
        XCTAssertEqual(p.levels, 7)
    }

    /// A seed is a `UInt32`, and a channel evaluating below 0 or above its range must not trap.
    func testTheSeedBridgeClampsRatherThanTraps() {
        let seed = parameter("noise.seed", of: .noise(Effect.Noise()))
        guard case .noise(let low)? = seed?.write(.noise(Effect.Noise()), -5) else {
            return XCTFail("not a noise")
        }
        XCTAssertEqual(low.seed, 0)
        guard case .noise(let high)? = seed?.write(.noise(Effect.Noise()), 1e18) else {
            return XCTFail("not a noise")
        }
        XCTAssertEqual(high.seed, UInt32.max)
    }

    // MARK: - The address space is not `EffectParams`

    /// **`EffectParams` cannot be the address space, and this is why in code.** Levels' five knobs
    /// and the whole Curves editor resolve into `lookupTable` and contribute *nothing* to it, so a
    /// track addressed through it would drive a value the render never reads.
    func testEffectParamsIsLossyForLevelsAndCurves() {
        XCTAssertEqual(Effect.levels(Effect.Levels(inputBlack: 0.2, gamma: 2.2)).params,
                       Effect.levels(Effect.Levels()).params,
                       "Levels contributes nothing to EffectParams — it resolves into lookupTable")
        XCTAssertNotEqual(Effect.levels(Effect.Levels(inputBlack: 0.2, gamma: 2.2)).lookupTable,
                          Effect.levels(Effect.Levels()).lookupTable)

        // ... and aliased: one `amount` field carries four unrelated quantities.
        XCTAssertEqual(Effect.sobel(Effect.Sobel()).params.amount,
                       Float(1.0 / 20.0.squareRoot()), accuracy: 1e-6)
        XCTAssertEqual(Effect.outline(Effect.Outline(width: 3)).params.amount, 3,
                       "Outline's *width* rides EffectParams.amount")
        XCTAssertEqual(Effect.noise(Effect.Noise(amount: 0.25)).params.amount, 0.25)
        XCTAssertEqual(Effect.sharpen(Effect.Sharpen(amount: 2)).params.amount, 2)
    }
}
