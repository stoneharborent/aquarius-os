// =============================================================================
// AquariusRings — the stick rings, in Game Mode's Decky tab
// =============================================================================
// HANDHELD IMAGE ONLY. Hand-written, no build step: Decky 3.2 import()s this
// file as an ES module and calls its default export. It uses only what Decky
// puts on `window` — SP_REACT (Steam's React), DFL (@decky/ui) and the loader's
// API connection — which is all a built plugin's bundle uses too. Checked
// against decky-loader v3.2.10 (frontend/src/plugin-loader.tsx) and a real
// store plugin's dist/index.js.
//
// The same choices as the desktop's Rings menu (the handheld GNOME extension)
// and `aq handheld rings`; the backend (main.py) runs that command. Brightness
// is not here: in Game Mode it is Steam's, and on the desktop the Keyboard
// slider.
//
// ⚠️ NAME must equal plugin.json's "name", or every call goes nowhere.
// =============================================================================

const NAME = "AquariusRings";

const React = window.SP_REACT;
const h = React.createElement;
const {PanelSection, PanelSectionRow, ButtonItem, ToggleField, Field, staticClasses} = window.DFL;

const connection = window.__DECKY_SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED_deckyLoaderAPIInit;
if (!connection)
    throw new Error("AquariusRings: Decky's loader API is not there");
let api;
try {
    api = connection.connect(2, NAME);
} catch (_error) {
    api = connection.connect(1, NAME);
}

const getRings = api.callable("get_rings");
const setRings = api.callable("set_rings");
const toast = (title, body) => api.toaster?.toast?.({title, body});

// [what aq is told, what the panel says, the colour in rings.conf]. Kept in
// step with PRESETS in /usr/libexec/aquarius-ally-rings.
const COLOURS = [
    ["white", "White", "ffffff"],
    ["blue", "AquariusOS blue", "8ab4ff"],
    ["steam", "Steam blue", "1a9fff"],
    ["xbox", "Xbox green", "40ff20"],
    ["x20", "X20 gold", "fff000"],
    ["cyan", "Cyan", "00e5ff"],
    ["green", "Green", "00ff40"],
    ["red", "Red", "ff0000"],
    ["orange", "Orange", "ff6000"],
    ["pink", "Pink", "ff2090"],
    ["purple", "Purple", "8000ff"],
];
const EFFECTS = [
    ["rainbow", "Rainbow (turning)"],
    ["cycle", "Every colour in turn"],
    ["breathe", "Breathing"],
];

function describe(rings) {
    if (!rings)
        return "…";
    if (rings.effect === "off")
        return "Off";
    if (rings.effect === "solid") {
        const c = COLOURS.find(([, , hex]) => hex === rings.colour);
        return c ? c[1] : `#${rings.colour}`;
    }
    const e = EFFECTS.find(([key]) => key === rings.effect);
    return e ? e[1] : rings.effect;
}

function isCurrent(rings, key) {
    if (!rings)
        return false;
    if (rings.effect === "solid")
        return COLOURS.some(([k, , hex]) => k === key && hex === rings.colour);
    return rings.effect === key;
}

// A small colour dot, so each colour row shows what it is.
const Swatch = ({hex}) => h("span", {
    style: {
        display: "inline-block", width: "0.9em", height: "0.9em", borderRadius: "50%",
        marginRight: "0.5em", verticalAlign: "middle", background: `#${hex}`,
    },
});

function Content() {
    const [rings, setState] = React.useState(null);
    const [busy, setBusy] = React.useState(false);

    React.useEffect(() => {
        getRings().then(setState).catch(e => toast("Rings", String(e)));
    }, []);

    const choose = async choice => {
        setBusy(true);
        try {
            setState(await setRings(choice));
        } catch (e) {
            toast("The rings could not be changed", String(e));
        } finally {
            setBusy(false);
        }
    };

    const on = rings ? rings.effect !== "off" : true;
    const row = (key, label, hex) => h(PanelSectionRow, {key},
        h(ButtonItem, {layout: "below", disabled: busy, onClick: () => choose(key)},
            hex ? h(Swatch, {hex}) : null,
            isCurrent(rings, key) ? `✓ ${label}` : label));

    return h(React.Fragment, null,
        h(PanelSection, {title: "Stick rings"},
            h(PanelSectionRow, null,
                h(ToggleField, {
                    label: "Rings", description: describe(rings), checked: on, disabled: busy,
                    onChange: value => choose(value ? "on" : "off"),
                }))),
        h(PanelSection, {title: "Colour"},
            ...COLOURS.map(([key, label, hex]) => row(key, label, hex))),
        h(PanelSection, {title: "Effect"},
            ...EFFECTS.map(([key, label]) => row(key, label, null))),
        h(PanelSection, null,
            h(PanelSectionRow, null,
                h(Field, {label: "Also on the desktop", description:
                    "Quick settings → Rings, or `aq handheld rings` in a terminal. It is one setting."}))));
}

const RingIcon = () => h("svg", {
    viewBox: "0 0 24 24", width: "1em", height: "1em", fill: "none",
    stroke: "currentColor", strokeWidth: 2,
}, h("circle", {cx: 12, cy: 12, r: 9}), h("circle", {cx: 12, cy: 12, r: 4}));

export default function () {
    return {
        name: NAME,
        titleView: h("div", {className: staticClasses.Title}, "Stick rings"),
        content: h(Content),
        icon: h(RingIcon),
        onDismount() {},
    };
}
