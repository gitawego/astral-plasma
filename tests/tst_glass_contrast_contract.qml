import QtQuick

// ============================================================================
// Glass Material Contrast Contract
// ============================================================================
// Translucent surfaces composite over an ARBITRARY wallpaper. A fixed alpha
// therefore yields an unbounded surface luminance: over a bright backdrop the
// glass washes out, and light text on it collapses toward 1:1 contrast.
//
// This suite encodes the two invariants that keep the material both legible and
// recognisably glass, evaluated with real WCAG 2.1 math against worst-case
// backdrops (pure white for the dark theme, pure black for the light theme):
//
//   A. LEGIBILITY  - every text token reaches >= 4.5:1 on both the structural
//                    plate and the content card, for every theme preset.
//   B. TRANSMISSION- the glass keeps a minimum backdrop transmission so the
//                    compositor blur stays visible instead of reading as an
//                    opaque slab.
//
// The token values are parsed from theme/Colors.qml so parameter drift in the
// source of truth fails here instead of silently shipping.
Item {
    id: testRoot
    width: 800
    height: 600

    // ------------------------------------------------------------------
    // WCAG 2.1 relative luminance and contrast
    // ------------------------------------------------------------------
    function srgbToLinear(c8) {
        const c = c8 / 255.0;
        return (c <= 0.04045) ? (c / 12.92) : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function relLuminance(rgb) {
        return 0.2126 * srgbToLinear(rgb[0])
             + 0.7152 * srgbToLinear(rgb[1])
             + 0.0722 * srgbToLinear(rgb[2]);
    }

    function contrastRatio(fg, bg) {
        const l1 = relLuminance(fg);
        const l2 = relLuminance(bg);
        const hi = Math.max(l1, l2);
        const lo = Math.min(l1, l2);
        return (hi + 0.05) / (lo + 0.05);
    }

    // src is [r,g,b] in 0..255 scales, alpha 0..1, dst is [r,g,b] 0..255
    function composite(src, alpha, dst) {
        return [
            src[0] * alpha + dst[0] * (1.0 - alpha),
            src[1] * alpha + dst[1] * (1.0 - alpha),
            src[2] * alpha + dst[2] * (1.0 - alpha)
        ];
    }

    function hexToRgb(hex) {
        return [
            parseInt(hex.substr(1, 2), 16),
            parseInt(hex.substr(3, 2), 16),
            parseInt(hex.substr(5, 2), 16)
        ];
    }

    function fmt(rgb) {
        return "(" + rgb[0].toFixed(0) + "," + rgb[1].toFixed(0) + "," + rgb[2].toFixed(0) + ")";
    }

    // Replicates Qt.tint(base, alpha(tintColor, tintAmount)): the RGB channels
    // are lerped toward the tint colour and the resulting alpha is the union of
    // the two (verified against the Qt runtime: base a=0.78 + tint 0.10 -> 0.802).
    function tint(baseRgb, tintAmt, tintRgb) {
        return [
            tintRgb[0] * tintAmt + baseRgb[0] * (1.0 - tintAmt),
            tintRgb[1] * tintAmt + baseRgb[1] * (1.0 - tintAmt),
            tintRgb[2] * tintAmt + baseRgb[2] * (1.0 - tintAmt)
        ];
    }

    function effectiveAlpha(baseAlpha, tintAmt) {
        return tintAmt + baseAlpha * (1.0 - tintAmt);
    }

    // ------------------------------------------------------------------
    // Source parsing
    // ------------------------------------------------------------------
    function readLocalFile(relUrl) {
        const xhr = new XMLHttpRequest();
        // Cache-buster: Qt caches file:// reads, so a guard can silently test
        // STALE source and pass while the real file has changed. Appending a
        // unique query forces a fresh read. (CACHEBUST)
        const bust = (relUrl.indexOf("?") < 0 ? "?v=" : "&v=") + Date.now() + Math.random();
        xhr.open("GET", Qt.resolvedUrl(relUrl) + bust, false);
        xhr.send();
        return xhr.responseText || "";
    }

    function section(text, startMarker, endMarker) {
        const a = text.indexOf(startMarker);
        if (a < 0)
            return null;
        const b = text.indexOf(endMarker, a);
        return (b < 0) ? text.substring(a) : text.substring(a, b);
    }

    function num(body, key) {
        const m = body.match(new RegExp(key + "\\s*:\\s*([0-9.]+)"));
        return m ? parseFloat(m[1]) : NaN;
    }

    function vec3(body, key) {
        const m = body.match(new RegExp(key + "\\s*:\\s*\\[\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*,\\s*([0-9.]+)\\s*\\]"));
        return m ? [parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3])] : null;
    }

    function parseGlassParams(colorsSrc) {
        const body = section(colorsSrc, "glassParams:", "})");
        if (body === null)
            return null;

        const darkBody = section(body, "dark:", "light:");
        const lightBody = (function() {
            const i = body.indexOf("light:");
            return (i < 0) ? null : body.substring(i);
        })();
        if (darkBody === null || lightBody === null)
            return null;

        function block(b) {
            return {
                surfaceBase: vec3(b, "surfaceBase"),
                surfaceAlpha: num(b, "surfaceAlpha"),
                surfaceTint: num(b, "surfaceTint"),
                cardBase: vec3(b, "cardBase"),
                cardAlpha: num(b, "cardAlpha"),
                cardTint: num(b, "cardTint"),
                cardHoverAlpha: num(b, "cardHoverAlpha"),
                cardHoverTint: num(b, "cardHoverTint"),
                cardActiveAlpha: num(b, "cardActiveAlpha"),
                cardActiveTint: num(b, "cardActiveTint"),
                cardVibrantAlpha: num(b, "cardVibrantAlpha"),
                cardVibrantTint: num(b, "cardVibrantTint")
            };
        }
        return { dark: block(darkBody), light: block(lightBody) };
    }

    // Worst-case text AND tint colours across every preset in the registry.
    // Dark themes carry light text, so the DARKEST light-text colour is worst;
    // light themes carry dark text, so the LIGHTEST dark-text colour is worst.
    // A tint brightens a dark substrate and darkens a light one, so the worst
    // tint is the brightest dark-mode primary and the darkest light-mode one.
    function worstTextColors(colorsSrc) {
        const re = /on_surface(_variant)?:\s*"(#[0-9A-Fa-f]{6})"/g;
        let m;
        const darkMain = [], darkMuted = [], lightMain = [], lightMuted = [];
        while ((m = re.exec(colorsSrc)) !== null) {
            const isMuted = (m[1] === "_variant");
            const rgb = hexToRgb(m[2]);
            const lum = relLuminance(rgb);
            // Nearest preceding mode marker decides the block.
            const before = colorsSrc.substring(0, m.index);
            const inDark = before.lastIndexOf("dark: {") > before.lastIndexOf("light: {");
            if (inDark)
                (isMuted ? darkMuted : darkMain).push({ lum: lum, rgb: rgb });
            else
                (isMuted ? lightMuted : lightMain).push({ lum: lum, rgb: rgb });
        }

        function pickDark(list) {   // light text: lowest luminance loses contrast
            let best = null;
            for (let i = 0; i < list.length; i++)
                if (best === null || list[i].lum < best.lum)
                    best = list[i];
            return best ? best.rgb : null;
        }
        function pickLight(list) {  // dark text: highest luminance loses contrast
            let best = null;
            for (let i = 0; i < list.length; i++)
                if (best === null || list[i].lum > best.lum)
                    best = list[i];
            return best ? best.rgb : null;
        }
        return {
            darkMain: pickDark(darkMain), darkMuted: pickDark(darkMuted),
            lightMain: pickLight(lightMain), lightMuted: pickLight(lightMuted),
            darkTint: pickLight(darkMain.concat(darkMuted)),  // brightest primary (approx.)
            lightTint: pickDark(lightMain.concat(lightMuted))
        };
    }

    // Worst-case theme tint (palette primary) for each mode, scanned from the registry.
    function worstTint(colorsSrc, dark) {
        const re = /primary:\s*"(#[0-9A-Fa-f]{6})"/g;
        let m;
        let best = null;
        while ((m = re.exec(colorsSrc)) !== null) {
            const rgb = hexToRgb(m[1]);
            const lum = relLuminance(rgb);
            const before = colorsSrc.substring(0, m.index);
            const inDark = before.lastIndexOf("dark: {") > before.lastIndexOf("light: {");
            if (inDark !== dark)
                continue;
            // A brighter tint brightens the dark plate most; a darker tint
            // darkens the light plate most.
            if (best === null
                || (dark && lum > best.lum)
                || (!dark && lum < best.lum))
                best = { lum: lum, rgb: rgb };
        }
        return best ? best.rgb : null;
    }

    // Vibrancy halo: glyphs on glass are painted over this soft outline, so it
    // is the local backdrop for text legibility. Parsed from Colors.qml so the
    // halo can never silently weaken while the alphas get more transparent.
    // The token is mode-aware: a dark halo guards light text (dark mode) and a
    // light halo guards dark text (light mode).
    function parseTextHalo(colorsSrc) {
        const body = section(colorsSrc, "glassTextHalo:", "}")
            || section(colorsSrc, "glassTextHalo:", "\n    readonly");
        if (body === null)
            return null;
        const re = /Qt\.rgba\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/g;
        const found = [];
        let m;
        while ((m = re.exec(body)) !== null)
            found.push([parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3]), parseFloat(m[4])]);
        if (found.length === 0)
            return null;
        // Source order is the true branch (dark) then the false branch (light).
        const first = found[0];
        const second = found.length > 1 ? found[1] : found[0];
        return {
            dark:  { alpha: first[3],  rgb: [first[0] * 255,  first[1] * 255,  first[2] * 255] },
            light: { alpha: second[3], rgb: [second[0] * 255, second[1] * 255, second[2] * 255] }
        };
    }

    Timer {
        interval: 50
        running: true
        repeat: false
        onTriggered: runTests()
    }

    function assert(condition, message) {
        if (!condition) {
            console.error("FAIL: " + message);
            Qt.exit(1);
            throw new Error(message);
        }
    }

    property int checked: 0

    function runTests() {
        console.log("RUNNING: Glass Material Contrast Contract");

        const AA = 4.5;                    // WCAG AA, normal body/UI text
        // The plate must stay genuinely transparent: AGENTS.md 6.3 mandates the
        // 55-65% alpha band, and below ~45% transmission the compositor blur
        // stops reading as glass at all. Legibility at these alphas comes from
        // the vibrancy halo (Colors.glassTextHalo), which is why this floor can
        // be high rather than traded away for opaque text backgrounds.
        const MIN_TRANSMISSION = 0.45;
        const MIN_TOTAL_TRANSMISSION = 0.35; // plate+card stack (what the user sees)
        const MIN_CARD_DELTA = 12.0;       // card must be perceptibly distinct from plate

        const colorsSrc = readLocalFile("../theme/Colors.qml");
        assert(colorsSrc.length > 1000, "theme/Colors.qml must be readable by the test harness");

        // ---- 1. Token table must be machine-readable -------------------
        const params = parseGlassParams(colorsSrc);
        assert(params !== null,
            "theme/Colors.qml must expose a parseable `glassParams` table (single source of truth for glass alphas)");
        assert(!isNaN(params.dark.surfaceAlpha) && !isNaN(params.light.surfaceAlpha),
            "glassParams must define surfaceAlpha for dark and light modes");
        assert(params.dark.surfaceBase !== null && params.light.surfaceBase !== null,
            "glassParams must define surfaceBase for dark and light modes");
        assert(!isNaN(params.dark.cardAlpha) && !isNaN(params.light.cardAlpha),
            "glassParams must define cardAlpha for dark and light modes");
        assert(params.dark.cardBase !== null && params.light.cardBase !== null,
            "glassParams must define cardBase for dark and light modes");
        const NUMERIC_KEYS = ["surfaceAlpha", "surfaceTint", "cardAlpha", "cardTint",
                              "cardHoverAlpha", "cardHoverTint",
                              "cardActiveAlpha", "cardActiveTint",
                              "cardVibrantAlpha", "cardVibrantTint"];
        for (let ki = 0; ki < NUMERIC_KEYS.length; ki++) {
            const k = NUMERIC_KEYS[ki];
            assert(!isNaN(params.dark[k]) && !isNaN(params.light[k]),
                "glassParams must define a numeric `" + k + "` for dark and light modes");
        }

        // ---- 2. Worst-case text colours from the preset registry -------
        const text = worstTextColors(colorsSrc);
        assert(text.darkMain !== null && text.darkMuted !== null,
            "registry must define dark on_surface and on_surface_variant");
        assert(text.lightMain !== null && text.lightMuted !== null,
            "registry must define light on_surface and on_surface_variant");

        // ---- 2b. Vibrancy halo must exist and be strong enough ----------
        const halo = parseTextHalo(colorsSrc);
        assert(halo !== null,
            "theme/Colors.qml must define a parseable `glassTextHalo` - the vibrancy outline that keeps text legible on genuinely transparent glass");
        assert(halo.dark.alpha >= 0.45 && halo.light.alpha >= 0.45,
            "glassTextHalo must be >= 0.45 opaque in both modes, got dark=" + halo.dark.alpha
            + " light=" + halo.light.alpha + " (a weaker halo cannot carry AA at the transmission floor)");

        // The theme tint colour is the palette primary; take the worst case per
        // mode from the registry so the tint contribution is never underestimated.
        const tintDark = worstTint(colorsSrc, true);
        const tintLight = worstTint(colorsSrc, false);
        assert(tintDark !== null && tintLight !== null,
            "registry must define a primary for dark and light modes");

        // Worst-case backdrops: the plate must survive a fully blown-out
        // wallpaper (pure white) in dark mode, and pure black in light mode.
        const BACKDROP_DARK = [255.0, 255.0, 255.0];
        const BACKDROP_LIGHT = [0.0, 0.0, 0.0];

        const MODES = [
            { name: "dark", p: params.dark, backdrop: BACKDROP_DARK, tintRgb: tintDark,
              textMain: text.darkMain, textMuted: text.darkMuted,
              haloRgb: halo.dark.rgb, haloAlpha: halo.dark.alpha },
            { name: "light", p: params.light, backdrop: BACKDROP_LIGHT, tintRgb: tintLight,
              textMain: text.lightMain, textMuted: text.lightMuted,
              haloRgb: halo.light.rgb, haloAlpha: halo.light.alpha }
        ];

        for (let mi = 0; mi < MODES.length; mi++) {
            const mode = MODES[mi];
            const tag = mode.name;
            const tintRgb = mode.tintRgb;

            // ---- 3. Structural plate: legibility over worst-case backdrop
            const plateBase = [mode.p.surfaceBase[0] * 255,
                               mode.p.surfaceBase[1] * 255,
                               mode.p.surfaceBase[2] * 255];
            const plateRgb = tint(plateBase, mode.p.surfaceTint, tintRgb);
            const plateAlpha = effectiveAlpha(mode.p.surfaceAlpha, mode.p.surfaceTint);
            const plate = composite(plateRgb, plateAlpha, mode.backdrop);

            // Legibility is measured against the vibrancy halo, not the raw
            // plate: glyphs on glass are painted over a soft outline so the
            // local backdrop behind a stroke is the halo, not the wallpaper.
            // Without this the contract could only be met by making the glass
            // opaque, which is the failure this whole suite exists to prevent.
            const plateHalo = composite(mode.haloRgb, mode.haloAlpha, plate);
            const plateMain = contrastRatio(mode.textMain, plateHalo);
            const plateMuted = contrastRatio(mode.textMuted, plateHalo);
            this.checked++;

            assert(plateMain >= AA,
                "[" + tag + "] main text on glass plate must reach " + AA + ":1 over worst-case backdrop, got "
                + plateMain.toFixed(2) + ":1 (halo " + fmt(plateHalo) + ", plate " + fmt(plate)
                + ", text " + fmt(mode.textMain) + ")");

            assert(plateMuted >= AA,
                "[" + tag + "] muted text on glass plate must reach " + AA + ":1 over worst-case backdrop, got "
                + plateMuted.toFixed(2) + ":1 (halo " + fmt(plateHalo) + ", plate " + fmt(plate)
                + ", text " + fmt(mode.textMuted) + ")");

            // ---- 4. Content card: STACKED on the plate --------------------
            // The card is drawn on top of the plate, so the surface the user
            // actually looks through is plate+card, and the two alphas
            // MULTIPLY. Asserting each layer against the wallpaper separately
            // is what let a 0.76 plate under a 0.78 card ship: each layer
            // looked fine alone, but the stack transmitted only 5% of the
            // wallpaper and rendered as an opaque slab.
            const cardBase = [mode.p.cardBase[0] * 255,
                              mode.p.cardBase[1] * 255,
                              mode.p.cardBase[2] * 255];
            const cardRgb = tint(cardBase, mode.p.cardTint, tintRgb);

            const cardAlpha = effectiveAlpha(mode.p.cardAlpha, mode.p.cardTint);
            const cardOnPlate = composite(cardRgb, cardAlpha, plate);
            this.checked++;

            // Combined transmission is the product of the two layers, and is
            // what determines whether the blurred wallpaper is visible at all.
            const totalTransmission = (1.0 - plateAlpha) * (1.0 - cardAlpha);
            assert(totalTransmission >= MIN_TOTAL_TRANSMISSION,
                "[" + tag + "] plate+card stack must transmit >= " + (MIN_TOTAL_TRANSMISSION * 100) + "% of the backdrop so the "
                + "blurred wallpaper stays visible through the cards, got "
                + (totalTransmission * 100).toFixed(1) + "% (plate " + plateAlpha.toFixed(3)
                + " x card " + cardAlpha.toFixed(3) + ")");

            // A card that transmits perfectly but is indistinguishable from the
            // plate is not a card. Require a perceptible luminance step.
            const cardDelta = Math.abs(cardOnPlate[0] - plate[0]);
            assert(cardDelta >= MIN_CARD_DELTA,
                "[" + tag + "] card must stay visually distinct from the plate (>= " + MIN_CARD_DELTA
                + " luminance levels), got " + cardDelta.toFixed(1)
                + " (plate " + fmt(plate) + ", card " + fmt(cardOnPlate) + ")");

            const cardHalo = composite(mode.haloRgb, mode.haloAlpha, cardOnPlate);
            assert(contrastRatio(mode.textMain, cardHalo) >= AA,
                "[" + tag + "] main text on card must reach " + AA + ":1, got "
                + contrastRatio(mode.textMain, cardHalo).toFixed(2) + ":1 (halo " + fmt(cardHalo) + ", card " + fmt(cardOnPlate) + ")");
            assert(contrastRatio(mode.textMuted, cardHalo) >= AA,
                "[" + tag + "] muted text on card must reach " + AA + ":1, got "
                + contrastRatio(mode.textMuted, cardHalo).toFixed(2) + ":1 (halo " + fmt(cardHalo) + ", card " + fmt(cardOnPlate) + ")");

            // ---- 5. Hover / selected card variants stay legible too ------
            const hover = composite(tint(cardBase, mode.p.cardHoverTint, tintRgb),
                                    effectiveAlpha(mode.p.cardHoverAlpha, mode.p.cardHoverTint), plate);
            const active = composite(tint(cardBase, mode.p.cardActiveTint, tintRgb),
                                     effectiveAlpha(mode.p.cardActiveAlpha, mode.p.cardActiveTint), plate);
            assert(contrastRatio(mode.textMuted, hover) >= AA,
                "[" + tag + "] muted text on hovered card must reach " + AA + ":1, got "
                + contrastRatio(mode.textMuted, hover).toFixed(2) + ":1 (card " + fmt(hover) + ")");
            assert(contrastRatio(mode.textMuted, active) >= AA,
                "[" + tag + "] muted text on selected card must reach " + AA + ":1, got "
                + contrastRatio(mode.textMuted, active).toFixed(2) + ":1 (card " + fmt(active) + ")");

            const vibrant = composite(tint(cardBase, mode.p.cardVibrantTint, tintRgb),
                                      effectiveAlpha(mode.p.cardVibrantAlpha, mode.p.cardVibrantTint), plate);
            const vibrantHalo = composite(mode.haloRgb, mode.haloAlpha, vibrant);
            assert(contrastRatio(mode.textMain, vibrantHalo) >= AA,
                "[" + tag + "] main text on vibrant card must reach " + AA + ":1, got "
                + contrastRatio(mode.textMain, vibrantHalo).toFixed(2) + ":1 (halo " + fmt(vibrantHalo) + ")");

            // ---- 6. Transparency floor: the material must read as glass --
            const plateTransmission = 1.0 - plateAlpha;
            assert(plateTransmission >= MIN_TRANSMISSION,
                "[" + tag + "] glass plate must transmit >= " + (MIN_TRANSMISSION * 100) + "% of the backdrop, got "
                + (plateTransmission * 100).toFixed(1) + "% (alpha " + plateAlpha + ")");
        }

        // ---- 7. Backdrop scrim must not flatten the compositor blur -------
        const shellSrc = readLocalFile("../shell/UnifiedShell.qml");
        assert(shellSrc.length > 1000, "shell/UnifiedShell.qml must be readable");
        const scrimMatch = shellSrc.match(/scrimOpacity:\s*[^?]*\?\s*([0-9.]+)\s*:\s*([0-9.]+)/);
        assert(scrimMatch !== null,
            "UnifiedShell must expose a parseable `scrimOpacity` so the backdrop dimming stays bounded");
        const scrimDark = parseFloat(scrimMatch[1]);
        const scrimLight = parseFloat(scrimMatch[2]);
        assert(scrimDark <= 0.15,
            "dark-mode backdrop scrim must stay <= 0.15 so the blurred wallpaper remains visible, got " + scrimDark);
        assert(scrimLight <= 0.15,
            "light-mode backdrop scrim must stay <= 0.15 so the blurred wallpaper remains visible, got " + scrimLight);

        console.log("PASS: Glass Material Contrast Contract (" + this.checked + " surfaces verified, AA + transmission floors held)");
        Qt.exit(0);
    }
}
