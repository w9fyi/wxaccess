# wxaccess User Guide

**Version 1.0 — macOS 14 Sonoma and later**

---

wxaccess is a free, native macOS weather radar viewer built around one principle: all weather data should be fully usable without touching the map. Every value the app fetches — radar intensity, storm alerts, outlooks, surface observations — is readable in a structured text panel navigable by VoiceOver, keyboard, or mouse.

This guide walks you from installation through every feature, with plain-English explanations and hands-on exercises you can try the moment the app opens.

---

## Table of Contents

1. [System Requirements](#system-requirements)
2. [Installation](#installation)
3. [First Launch](#first-launch)
4. [Interface Overview](#interface-overview)
5. [Radar Fundamentals](#radar-fundamentals)
6. [Selecting a Radar Site](#selecting-a-radar-site)
7. [Radar Products and What They Show](#radar-products-and-what-they-show)
8. [Reading the Radar Display](#reading-the-radar-display)
9. [Click-to-Probe](#click-to-probe)
10. [Loop Animation](#loop-animation)
11. [Archive and Historical Data](#archive-and-historical-data)
12. [NWS Alerts and Warnings](#nws-alerts-and-warnings)
13. [SPC Convective Outlooks](#spc-convective-outlooks)
14. [SPC Mesoscale Discussions](#spc-mesoscale-discussions)
15. [SPC Storm Reports](#spc-storm-reports)
16. [Storm Cells (SCIT)](#storm-cells-scit)
17. [Surface Observations](#surface-observations)
18. [Satellite Imagery](#satellite-imagery)
19. [Model and Analysis Layers](#model-and-analysis-layers)
20. [Custom Placefiles](#custom-placefiles)
21. [Sonification](#sonification)
22. [Accessibility Panel Reference](#accessibility-panel-reference)
23. [Settings and Preferences](#settings-and-preferences)
24. [Keyboard Shortcuts](#keyboard-shortcuts)
25. [Filing a Bug Report](#filing-a-bug-report)
26. [Data Sources](#data-sources)

---

## System Requirements

| Requirement | Minimum |
|---|---|
| macOS | 14.0 (Sonoma) or later |
| Internet connection | Required for all data |
| Disk space | ~50 MB for app + Xcode build cache |
| Xcode (build from source) | 16.0 or later |

No account, subscription, or API key is required. All data sources used by wxaccess are free and public.

---

## Installation

### Building from Source

wxaccess is distributed as source code. You will need Xcode (free from the Mac App Store) and the `xcodegen` command-line tool.

**Step 1 — Install Xcode**

Open the Mac App Store, search for "Xcode", and install it. After installation, open it once to accept the license agreement.

**Step 2 — Install XcodeGen**

Open Terminal and run:

```sh
brew install xcodegen
```

If you do not have Homebrew, install it first from [brew.sh](https://brew.sh).

**Step 3 — Clone or download the project**

```sh
git clone https://github.com/w9fyi/wxaccess.git
cd wxaccess
```

**Step 4 — Generate the Xcode project and build**

```sh
xcodegen generate
xcodebuild -scheme wxaccess -configuration Release build ARCHS=arm64
```

**Step 5 — Copy the app to your Applications folder**

After the build succeeds, Xcode places the built app inside `~/Library/Developer/Xcode/DerivedData/`. The easiest way to find and install it:

```sh
open "$(find ~/Library/Developer/Xcode/DerivedData -name 'wxaccess.app' -maxdepth 6 | head -1)/.."
```

This opens a Finder window containing `wxaccess.app`. Drag it to `/Applications`.

---

## First Launch

When you open wxaccess for the first time, macOS will ask for two permissions:

**Location access** — Optional. The app uses your location only to identify the nearest radar site when you click "Use My Location." You can decline and select a site manually.

**Notifications** — Recommended. The app sends desktop notifications when a Tornado Warning or Severe Thunderstorm Warning is issued for any area on screen. You can allow this now or enable it later in System Settings → Notifications → wxaccess.

After granting (or declining) permissions, the app loads the default radar site — KEWX (Austin/San Antonio, TX) — and fetches the most recent radar scan. The initial load takes a few seconds while the app downloads and decodes the radar data.

---

## Interface Overview

The wxaccess window is divided into three areas:

```
+------------------------------------------------------------------+
|  Toolbar: Site | Product | Tilt | Palette | Overlays | Satellite |
|          Model | Resolution | Opacity | Refresh                  |
+------------------+-----------------------------------------------+
|                  |                                               |
|  Site Selector   |         Map Canvas                            |
|  (sidebar)       |   (radar overlay on interactive map)          |
|                  |                                               |
|  Search: [    ]  |    [range rings, alert polygons, markers]     |
|                  |                                               |
|  KEWX Austin TX  |    [color scale legend, bottom-right]         |
|  KGRK Temple     |                                               |
|  KHGX Houston    |                                               |
|  ...             |                                               |
|                  |                                               |
+------------------+-----------------------------------------------+
|  Status bar: KEWX REF 0.5° | 23:15 UTC | VCP 212 | [Refresh]    |
+------------------------------------------------------------------+
|  Data Summary [disclosure group]                                  |
|    Radar | Gate Probe | Animation | Alerts | Outlooks | ...      |
+------------------------------------------------------------------+
```

**Sidebar** — The site selector shows all ~160 WSR-88D radar stations. Type in the search field to filter by ICAO code, city, or state. Click any row to switch sites.

**Toolbar** — Controls for radar product, tilt angle, color palette, opacity, resolution, and overlay toggles. All items are labeled for VoiceOver.

**Map canvas** — The interactive radar map. Pan by dragging, zoom with pinch or scroll. Click anywhere on the radar to probe the value at that point.

**Status bar** — Shows the currently displayed site, product, tilt angle, scan time (UTC), and VCP number. A manual Refresh button sits at the right.

**Data Summary panel** — A collapsible panel below the map containing all data in plain text. Everything visible on the map is also represented here. VoiceOver users can navigate this panel entirely without visiting the map.

---

## Radar Fundamentals

### What is NEXRAD?

NEXRAD (Next-Generation Radar) is the national network of 160 Doppler weather radars operated by the National Weather Service. Each radar rotates continuously, sweeping the sky at multiple elevation angles every few minutes. The raw data is transmitted to NOAA and made available publicly within minutes of collection.

wxaccess downloads this raw data directly from NOAA's public storage at no cost.

### How the radar works

Each radar transmits a pulse of microwave energy and listens for energy reflected back from precipitation. The delay between transmission and reception tells the radar how far away the precipitation is. The strength of the returned signal tells it how much precipitation is there.

A radar sweep covers 360 degrees of azimuth and roughly 230 km (143 miles) of range. Within that area, the radar samples thousands of small volumes of air called **range gates**, each about 0.25 to 1 km across.

### Reading the color scale

The color scale legend in the bottom-right corner of the map shows the range of values for the currently displayed product. Colors on the left (cool tones: black, blue, green) represent low values; colors on the right (warm tones: yellow, orange, red, purple) represent high values.

For the most common product — Base Reflectivity — the scale runs roughly like this:

```
  Black   Blue    Green   Yellow   Orange   Red    Purple   White
  |-------|--------|--------|--------|--------|-------|--------|
  0      10      20      30       40       50      60      70+ dBZ
  (none) (light) (light) (light)  (heavy)  (very)  (ext.)  (hail)
                  drizzle  rain    rain     heavy   severe
```

---

## Selecting a Radar Site

The sidebar on the left lists all WSR-88D radar sites in the United States and territories. Sites are grouped by state and territory.

### Searching for a site

Type in the search field at the top of the sidebar. You can search by:

- **ICAO code** — the four-letter identifier (e.g., `KEWX`, `KDFW`, `KLOT`)
- **City name** — partial matches work (e.g., `Austin`, `Chicago`)
- **State** — two-letter abbreviation or full name (e.g., `TX`, `Texas`)

Click any row to load that site. The map pans and zooms to center on the new radar location.

### Use My Location

Click **Use My Location** at the bottom of the sidebar. The app finds the WSR-88D site with the best coverage of your GPS coordinates and selects it automatically. This requires Location permission.

### Setting a default site

If you always want the app to open with a specific site, open **Settings** (`Cmd+,`) and choose your preferred site from the Default Site picker. That site will be selected automatically every time the app launches.

> **Try it now:** Type `KDFW` in the search field to load the Dallas/Fort Worth radar. Then type `Chicago` to find KLOT (Chicago, IL). Notice how the map re-centers on each new site.

---

## Radar Products and What They Show

wxaccess provides two tiers of radar data: **Level 2** (the raw dual-polarization scan from the radar dish) and **Level 3** (processed products derived from the Level 2 data by NWS algorithms).

Use the **Product** picker in the toolbar to switch between products.

### Level 2 Products (dual-pol moments)

These are the rawest, highest-resolution measurements available from the radar. Each tells you something different about what is in the atmosphere.

| Product | Full Name | What It Shows | Useful For |
|---|---|---|---|
| **REF** | Reflectivity | How much precipitation is returning signal, in dBZ | Seeing where rain or storms are |
| **VEL** | Velocity | How fast precipitation is moving toward or away from the radar, in m/s | Finding rotation, wind shear |
| **SW** | Spectrum Width | How variable the wind speeds are within a gate | Detecting turbulence and rotation |
| **ZDR** | Differential Reflectivity | Ratio of horizontal to vertical return — indicates drop shape | Identifying large drops, hail, ice |
| **RHO** | Correlation Coefficient | How uniform the particles in a gate are | Separating rain from debris or clutter |
| **PHI** | Differential Phase | Phase shift between horizontal and vertical pulses | Estimating rainfall rate precisely |

**Reflectivity (REF) — the most common view.** Values in decibels of reflectivity (dBZ):

| Range | What it usually means |
|---|---|
| Below 20 dBZ | Drizzle or very light rain; fog |
| 20–35 dBZ | Light to moderate rain |
| 35–50 dBZ | Moderate to heavy rain |
| 50–60 dBZ | Very heavy rain; possibly small hail |
| 60–65 dBZ | Large hail likely; severe thunderstorm |
| Above 65 dBZ | Extreme — giant hail, very intense core |

**Velocity (VEL) — detecting rotation.** Velocity shows motion relative to the radar. Negative values (typically cooler colors) mean motion *toward* the radar; positive values (warm colors) mean motion *away* from the radar. When you see a tight couplet of strong inbound and outbound values side by side, the atmosphere is rotating — a potential precursor to a tornado.

**Correlation Coefficient (RHO) — finding non-rain targets.** Values above 0.97 indicate uniform rain or snow. Values below 0.85 often indicate ground clutter, birds, insects, smoke, or tornado debris. During a confirmed tornado, a debris ball — a region of very low CC values at the surface — is one of the most reliable confirmation signatures.

### Level 3 Products (processed)

| Product | Code | What It Shows |
|---|---|---|
| Super-Res Base Reflectivity | N0Q | High-resolution composite reflectivity |
| Super-Res Velocity | N0U | High-resolution radial velocity |
| Echo Tops | EET | Estimated top of radar echoes in thousands of feet |
| Digital VIL | DVL | Vertically Integrated Liquid — water content of a column |
| Storm Total Precip | STP | Cumulative rainfall estimate since last reset |
| One-Hour Precip | OHP | Estimated rainfall in the past hour |

**Echo Tops (EET)** measures how high storms reach. Ordinary thunderstorms top out at 30,000–40,000 ft. Severe storms often exceed 50,000 ft. Overshooting tops visible on echo tops are a sign of an explosive, powerful updraft.

**VIL (Vertically Integrated Liquid)** aggregates all the water in a column. Values above 30 kg/m² suggest heavy rain is likely; values above 50 suggest hail is possible. Meteorologists often watch for "VIL of the day" — the locally significant threshold where large hail becomes probable.

> **Try it now:** Load the KEWX site and switch the Product picker to **VEL**. Notice the reds and greens. If there is no active precipitation, the velocity field will be mostly noise. On an active storm day, look for a tight red-green couplet — that is rotation.

---

## Reading the Radar Display

### Elevation tilt angles

Each radar scan is not a flat slice of the sky — the beam is angled slightly upward. At longer ranges, a 0.5° tilt is already sampling the atmosphere thousands of feet above the ground. Higher tilts see higher into storms.

Use the **Tilt** picker in the toolbar to switch between the five available elevation angles:

| Angle | Typical use |
|---|---|
| 0.5° | Surface precipitation; tornado debris; lowest coverage |
| 1.5° | Low-level structure; hook echoes; inflow notches |
| 2.4° | Mid-level storm structure |
| 3.4° | Updraft regions and bounded weak echo regions |
| 4.3° | Upper-level storm core; hail signature aloft |

For general monitoring, 0.5° is the correct default. If you are studying a specific storm in detail, step through the tilts to build a three-dimensional picture.

### Color palettes

Three color schemes are available in the **Palette** picker:

**NWS Standard** — The color table used by the National Weather Service's own public displays. Green through yellow, orange, red, and purple. Familiar to most weather enthusiasts.

**GRLevel3 Default** — An enhanced-contrast table widely used by storm chasers. Slightly different shade assignments emphasize moderate reflectivity values.

**Colorblind-Friendly** — A blue-to-amber scale that avoids the red-green distinction entirely. Recommended for users with deuteranopia or protanopia.

### Radar opacity

The opacity slider (30–100%, default 75%) controls how transparent the radar overlay is. At 100%, the map underneath is mostly obscured. At 30%, the radar is ghosted over the map and underlying geography is clearly visible.

### Image resolution

The resolution picker (512 / 1024 / 2048 px) controls the pixel density of the radar image rendered over the map. Higher resolution shows finer detail but takes longer to render. For most uses, 1024 is a good balance. Use 2048 when zoomed in close to a single storm.

### Range rings

Enable **Range Rings** in Settings to draw concentric circles at 50, 100, 150, and 230 km from the radar site. The outermost ring (230 km) marks the practical edge of the radar's useful coverage — data beyond this distance is sampled high above the ground and is unreliable for surface precipitation.

---

## Click-to-Probe

Click anywhere on the map while radar data is loaded. The app reads the radar value at the exact gate closest to the point you clicked and reports it in the Data Summary panel, where it is also announced as a VoiceOver live region update.

The probe result includes:

- **Product and value** — e.g., "Reflectivity: 52.3 dBZ"
- **Bearing** — the compass direction from the radar site to the point you clicked, expressed as a cardinal direction (N, NNE, NE, etc.)
- **Range** — distance in km from the radar site

Example output: *"Reflectivity: 52.3 dBZ, ESE 78 km from KEWX"*

This feature is especially useful when a specific storm cell shows an impressive color but you want the exact numeric value rather than a visual estimate.

> **Try it now:** Load KEWX with the REF product. If any precipitation is on screen, click directly on the most intense (brightest red or purple) area. The Data Summary panel will immediately show the dBZ value, bearing, and range. If there is no precipitation, click anywhere on the map — the result will show a value near 0 or report "no data" for gates with no return.

---

## Loop Animation

Loop animation plays the most recent radar scans in sequence so you can see how storms are moving and evolving.

### Starting and stopping

- Press **Cmd+L** to toggle animation on or off.
- Click the **Play** button in the animation controls area of the toolbar.

### Playback controls

| Control | Action |
|---|---|
| Play / Pause | Start or stop automatic frame advance |
| Step Forward | Advance one frame (also usable while paused) |
| Step Back | Go to the previous frame |
| Speed: Slow | 1.2 seconds per frame |
| Speed: Normal | 0.6 seconds per frame |
| Speed: Fast | 0.25 seconds per frame |

The animation loops through up to 10 of the most recent scans. For a 5-minute-interval radar, that covers roughly the past 50 minutes of history.

Each frame change is announced in the Data Summary panel with the frame number and scan time, so VoiceOver users can follow animation progress without watching the map.

> **Try it now:** Press **Cmd+L** to start the loop. Switch Speed to **Slow** and watch storms move across the map from west to east (typical for mid-latitude North America). Then switch to **Fast** to get a quick sense of the motion direction and storm organization.

---

## Archive and Historical Data

wxaccess can load radar data from any point in NOAA's archive, which extends back to 1991 for most sites.

### Selecting a date

Use the **Date Picker** in the toolbar to choose any calendar date up to and including today. After selecting a date, the app fetches the list of available scans and populates the **Scan Time Picker**.

### Selecting a scan time

The Scan Time Picker lists all available scans for the selected site and date, displayed in UTC. Click any row to load that specific scan.

Times are shown in UTC (Coordinated Universal Time), which does not change for daylight saving. Central Time is UTC-6 in winter and UTC-5 in summer, so a storm at 8:00 PM CDT appears as 01:00 UTC the next calendar day.

> **Try it now:** Any day with significant weather makes a good archive exercise. Select a date from a few weeks ago and load the KEWX site. Scan through the available times to see whatever precipitation was in the region. Switching to loop animation over archived data works exactly the same as with live data.

---

## NWS Alerts and Warnings

The National Weather Service issues alerts when hazardous weather is occurring or expected. wxaccess fetches active alerts for the entire country every five minutes and displays them on the map as color-coded polygon overlays.

### Alert severity

| Color on map | Alert type | What it means |
|---|---|---|
| Red (solid) | Tornado Warning | A tornado has been detected by radar or confirmed by a spotter. Take shelter immediately. |
| Orange (solid) | Severe Thunderstorm Warning | A storm with 58+ mph winds or 1" hail has been detected or is expected imminently. |
| Red (lighter) | Tornado Watch | Conditions are favorable for tornado development. Remain alert. |
| Yellow | Severe Thunderstorm Watch | Conditions favor severe thunderstorms. |
| Green | Flash Flood Warning | Flash flooding is occurring or imminent. |
| Cyan | Flash Flood Watch | Flash flooding is possible. |
| Various | Other advisories | Winter storm, dense fog, heat, high wind, etc. |

### Warning vs. Watch — the key distinction

A **Watch** means conditions are favorable. Go about your plans, but stay aware and have a plan ready.

A **Warning** means a hazard is imminent or occurring. Act now — a Tornado Warning means a tornado has been detected and you need to take shelter immediately.

### Viewing alert details

Click any alert polygon on the map, or open the Alerts List by pressing the **Alerts** button in the toolbar. Selecting an alert shows:

- Event name and headline
- The full NWS text, including what to do and what to expect
- Who issued it (e.g., "NWS Austin/San Antonio TX")
- Effective time and expiration time
- Severity category (Extreme, Severe, Moderate, Minor)

### Desktop notifications

For Tornado Warnings and Severe Thunderstorm Warnings covering any area currently visible on the map, wxaccess sends a desktop notification with a chime. This happens even if the app is in the background or minimized. Notifications are delivered by macOS and respect your Focus modes.

> **Try it now:** If there are no active alerts in your region, switch to a site in a currently active region. The status bar badge shows the number of active alerts. Click any red polygon on the map to read the full NWS text for that warning.

---

## SPC Convective Outlooks

The Storm Prediction Center (SPC) in Norman, Oklahoma issues daily forecasts of severe thunderstorm potential across the contiguous United States. These outlooks are updated several times per day — sometimes more frequently during active weather patterns.

### What a convective outlook is

An outlook is a probability forecast: given today's atmosphere, how likely are severe thunderstorms (tornadoes, large hail, damaging winds) in each region? The SPC draws polygons around areas of concern and assigns them a risk category.

### Risk categories

wxaccess displays SPC outlooks as semi-transparent polygon overlays, colored by risk category:

| Category | Color | What it means |
|---|---|---|
| General Thunderstorm | Green | Non-severe thunderstorms are possible |
| Marginal (MRGL) | Light green | Severe weather is possible but isolated or brief |
| Slight (SLGT) | Yellow | Scattered severe storms; a few significant severe events possible |
| Enhanced (ENH) | Orange | Numerous severe storms likely; some significant |
| Moderate (MDT) | Red | Widespread severe weather; significant tornado/hail/wind events likely |
| High (HIGH) | Magenta/Purple | Particularly dangerous situation; widespread violent tornadoes or derechos likely |

A "High" risk day is rare — fewer than 10 are issued per year — and always corresponds to a very significant weather threat.

### Viewing Days 1, 2, and 3

Use the SPC Outlooks toggle in the toolbar to switch between Day 1 (today), Day 2 (tomorrow), and Day 3. Day 1 outlooks are the most precise; Day 3 outlooks cover larger areas with lower confidence.

The Data Summary panel shows the highest risk category for each day and the number of distinct risk areas.

> **Try it now:** Press the Overlays button in the toolbar and enable SPC Convective Outlooks. If it is spring in the United States, there is likely a Day 1 outlook active somewhere. Even in quiet weather, a "General Thunderstorm" (green) area often covers parts of the Southeast or Gulf Coast.

---

## SPC Mesoscale Discussions

A Mesoscale Discussion (MD) is a short-fuse product from the SPC that highlights a developing weather situation before a watch is issued. Think of it as the SPC saying: "We are watching this area closely. A watch may be needed in the next 1–3 hours."

MDs appear as **dashed polygon outlines** on the map. Each MD includes:

- A discussion number (e.g., "MD #2847")
- A brief description of the threat ("Concerning: organized convection and supercell potential")
- The affected area
- Expiration time

MDs are updated as conditions evolve and expire automatically once the threat passes or a watch is issued.

> **Try it now:** Enable the Overlays menu → Mesoscale Discussions. On an active severe weather day, you will typically see 1–3 dashed polygon outlines. On a quiet day, there may be none. Check the Data Summary panel's Mesoscale Discussions section to read the text of any active MDs.

---

## SPC Storm Reports

Throughout each day, the SPC collects reports of tornado touchdowns, hail sightings, and damaging wind events from trained weather spotters, emergency managers, and automated sources. These appear on the map as markers, updated continuously.

### Report types

| Marker | Type | Reported as |
|---|---|---|
| Tornado icon | Tornado | F-scale rating (F0 through F5) |
| Diamond | Hail | Size in inches (e.g., 1.75" = golf ball) |
| Wind barb | Damaging wind | Speed in mph |

### Hail size reference

| Size | Approximate diameter | Common comparison |
|---|---|---|
| 0.25" | Pea | Pea |
| 0.75" | Penny | Penny/dime |
| 1.00" | Quarter | Quarter |
| 1.75" | Golf ball | Golf ball |
| 2.00" | Hen egg | Hen egg |
| 2.75" | Baseball | Baseball |
| 4.00" | Softball | Softball |

### Viewing report details

Click any storm report marker on the map to see the report details: time, location, county, state, reporter, and any additional comments.

The Data Summary panel shows a count of each type: "3 tornado, 5 hail, 2 wind" for the current day.

> **Try it now:** Enable the Overlays menu → Storm Reports. On any given day, you can typically find hail reports somewhere in the continental US. These reports appear even on days without major outbreaks — isolated convection produces reportable hail regularly.

---

## Storm Cells (SCIT)

Storm Cell Identification and Tracking (SCIT) is an NWS algorithm that automatically locates individual convective cells in the radar volume, assigns each one a two-character identifier, and calculates where each cell has been and where it is likely to go.

wxaccess fetches the SCIT output from the NEXRAD Level 3 NST (Storm Tracking Information) product, which is updated every radar volume scan — approximately every 5 minutes.

### What the overlay shows

Enable **Overlays → Storm Cells** to display three types of information:

**Orange markers** — One marker per identified storm cell. The marker's glyph shows the cell's two-character identifier (e.g., "K2", "A1"). Cell IDs are assigned by the NWS algorithm and persist as long as the cell remains trackable; a new or merged cell gets a new ID.

**White dashed lines** — The cell's past track, drawn from its oldest known position to its current location. The dashes give you an immediate visual read of where the storm came from and how fast it has been moving.

**Orange dotted lines** — The SCIT algorithm's forecast track, showing where the cell is expected to be in approximately 30 and 60 minutes, based on its recent motion vector.

### What the numbers mean

| Field | Description |
|---|---|
| Cell ID | Two-character NWS identifier, e.g. "A2" |
| Bearing from radar | Compass direction from the radar site to the cell |
| Range from radar | Distance in km from the radar antenna |
| Motion direction | Where the cell is heading (compass direction) |
| Motion speed | Estimated speed in km/h, derived from current→forecast vector |

### How the algorithm works

The SCIT algorithm runs inside the NWS radar product generator (RPG) after each volume scan. It identifies regions of reflectivity exceeding an internal threshold, computes each region's centroid, and attempts to match centroids from scan to scan to form continuous tracks. Cells that cannot be matched between consecutive scans are treated as new cells and assigned a fresh ID.

Because SCIT relies on centroid matching, it works best on well-organized, discrete convective cells (supercells, organized multicell clusters). It is less reliable for widespread stratiform rain, fast-evolving storm clusters, or cells near the edges of the radar's coverage area.

### VoiceOver and keyboard access

The Data Summary panel → **Storm Cells** section lists every tracked cell with a plain-English description. Example:

> *Cell K2: NNE 216 km from radar, moving NNW at 12 km/h*

When Storm Cells is enabled and data is loaded, the panel shows:

- Total number of cells being tracked
- For each cell (up to 5): ID, bearing and range from the radar, and motion direction and speed
- If more than 5 cells are tracked, a count of the remaining cells

Each orange map marker is fully labeled for VoiceOver — pressing VO+Space on a marker announces the same description as the Data Summary panel.

### Limitations and what SCIT cannot tell you

SCIT tells you **where cells are and where they are going**, but it does not tell you:

- **Severity** — A cell tracked by SCIT may be anything from a 20 dBZ rain shower to a 70 dBZ supercell. Always check the radar reflectivity and velocity to assess intensity.
- **Tornado potential** — SCIT does not indicate rotation. Use the Velocity (VEL) product and check for NWS Tornado Warnings for that information.
- **Exact future location** — The forecast track is a linear extrapolation of recent motion. Cells that turn, accelerate, or merge will deviate from the forecast.

SCIT data is only available when the NST product is present on the THREDDS server for the selected site and date. Quiet-weather days with no organized convection will show zero tracked cells, which is correct — no cells means no tracked cells.

> **Try it now:** Switch to a site in an area with active thunderstorms (check Overlays → Storm Reports to find a region with current hail or tornado reports). Enable Overlays → Storm Cells. Orange markers will appear over any cells the SCIT algorithm has identified. Open the Data Summary panel and navigate to Storm Cells — VoiceOver will read each cell's range and motion direction. Tap a marker on the map to hear a full description of that individual cell.

---

## Surface Observations

wxaccess overlays METAR surface observations from thousands of aviation weather stations, color-coded by flight category. This gives you an instant picture of low-level visibility and ceiling conditions across a region.

### Flight categories

Flight categories are used by pilots to determine what type of flying conditions are present, but they also serve as a quick shorthand for ceiling and visibility for anyone interested in surface weather.

| Color | Category | Ceiling and Visibility |
|---|---|---|
| Green | VFR (Visual Flight Rules) | Ceiling above 3,000 ft AND visibility above 5 miles |
| Blue | MVFR (Marginal VFR) | Ceiling 1,000–3,000 ft OR visibility 3–5 miles |
| Red | IFR (Instrument Flight Rules) | Ceiling 500–1,000 ft OR visibility 1–3 miles |
| Magenta | LIFR (Low IFR) | Ceiling below 500 ft OR visibility below 1 mile |

Each station marker shows the ICAO identifier. Selecting a station in the Data Summary panel or clicking it on the map shows:

- Temperature and dew point (°F or °C)
- Wind direction and speed (e.g., "SE 12 kt")
- Altimeter setting (inHg)
- Sky condition (CLR, FEW, SCT, BKN, OVC)

### Using surface obs with radar

Surface observations are most useful overlaid with radar to understand where precipitation is reaching the ground and what type it is. A station reporting OVC (overcast) with low temperature and dew point close together underneath a green (20 dBZ) reflectivity signature suggests light drizzle or freezing drizzle.

> **Try it now:** Enable Overlays → Surface Observations. Zoom out to see a wide area. Notice the color distribution — a line of IFR (red) stations often follows a cold front or a marine layer boundary. Look for stations where the temperature and dew point are within 2°F of each other; those locations are likely in fog or low stratus.

---

## Satellite Imagery

wxaccess displays imagery from GOES-16, the National Oceanic and Atmospheric Administration's primary geostationary weather satellite stationed over the eastern United States. GOES-16 provides imagery every 5 minutes.

Satellite tiles are served through the Iowa State University Mesonet cache, which processes the raw satellite data into map-compatible tiles.

### Satellite products

Press the **Satellite** button in the toolbar to enable the satellite overlay. Three products are available:

**Visible (0.64 µm)**

This is the closest to what your eye would see from space — sunlight reflected off clouds and the surface. Cloud texture, depth, and organization are clearest in visible imagery. Anvil clouds from thunderstorms, spiral banding around hurricanes, and fog layers over valleys all stand out.

*Limitation:* Visible imagery only works when sunlight is present. At night, this channel goes dark.

**Infrared (10.3 µm)**

Infrared imagery measures thermal emission. Cold cloud tops appear bright white; warm surfaces appear dark. Because cloud-top temperature decreases with altitude, very tall storm clouds (high, cold tops) appear brilliant white while low clouds appear gray.

Infrared works 24 hours a day and is the primary imagery for nighttime storm tracking.

*Reading the colors:* In the standard enhancement, pure white indicates cloud tops colder than -40°C (storm tops above 30,000 ft). Gray indicates mid-level clouds. Dark gray or black indicates the warm surface.

**Water Vapor (6.9 µm)**

Water vapor imagery does not show clouds directly — it shows the moisture content of the mid and upper atmosphere (roughly 15,000–40,000 ft). Bright areas indicate high moisture; dark areas (called "dry slots") indicate dry, descending air.

Water vapor imagery is invaluable for tracking jet stream patterns, identifying areas of upper-level divergence that favor storm development, and seeing large-scale features that radar alone misses.

> **Try it now:** Enable the satellite overlay and select **Infrared**. Zoom out to see the full eastern United States. Look for any bright white areas — those are the tallest storm tops in the country at this moment. Compare the satellite image with the radar overlay (you can display both simultaneously). Do the bright IR cores align with the highest reflectivity values?

---

## Model and Analysis Layers

Weather models use current atmospheric observations to forecast future conditions. wxaccess displays model output from two sources, accessible via the **Model** button in the toolbar.

### HRRR — High-Resolution Rapid Refresh

The HRRR is a high-resolution numerical weather prediction model updated hourly by NOAA. It assimilates radar data and produces forecasts up to 18 hours ahead at 3-km resolution over the contiguous United States.

**Available HRRR products:**

| Product | What It Shows |
|---|---|
| Simulated Reflectivity | What the radar would look like if the model is correct |
| Simulated Reflectivity + Precip Type | Reflectivity with rain/snow/ice/mixed type indicators |

Use the **Forecast Offset** picker to step through analysis (now), +1h, +2h, +3h, +6h, +12h, and +18h.

**How to use simulated reflectivity:** Compare the HRRR's simulated reflectivity for the next few hours against what the radar is currently showing. If the model is accurately tracking existing storms, its short-term forecast is likely to be reliable. If the model is badly misplacing current storms, treat its forecast with more skepticism.

### MRMS — Multi-Radar Multi-Sensor

MRMS is a near-real-time analysis product that merges data from all CONUS radar sites into a seamless national composite, supplemented by surface observations, lightning data, and model output.

**Available MRMS products:**

| Product | What It Shows |
|---|---|
| Composite Radar | Seamless merged reflectivity for the entire country |
| 1-Hour QPE | Quantitative precipitation estimate for the past hour |

MRMS Composite Radar is useful when you want a big-picture view without selecting a specific radar site. The QPE product shows estimated rainfall totals and is useful for assessing flash flood potential.

> **Try it now:** Enable the model overlay and select **HRRR Simulated Reflectivity**. Step the Forecast Offset forward to +3h. Then look at the actual radar. Do the model's predicted storm locations and intensities roughly match what is currently happening? This is a quick way to evaluate model accuracy in real time.

---

## Custom Placefiles

Placefiles are data overlays in a text-based format originally designed for GRLevel3, now supported by most professional radar applications. They allow anyone to distribute custom map data — storm chaser positions, tornado tracks, earthquake epicenters, amateur radio repeater locations, Skywarn spotter positions, and more.

### Adding a placefile

1. Open **Settings** (`Cmd+,`) and scroll to the **Placefiles** section.
2. Paste a URL (must begin with `https://` or `http://`) into the text field.
3. Click **Add**.

The placefile is fetched immediately and displayed on the map. It will refresh automatically based on the interval specified in the placefile itself (minimum 30 seconds).

### What placefiles can show

- **Text labels** — Point annotations at specific coordinates
- **Lines** — Polylines connecting multiple points with customizable width and color
- **Polygons** — Filled or outlined regions

The Data Summary panel lists each loaded placefile by URL and shows up to 10 point labels for VoiceOver navigation.

### Removing a placefile

In Settings → Placefiles, each entry has a Remove button. Click it to immediately remove that placefile from the map.

> **Try it now:** AllisonHouse and several university meteorology departments publish public placefiles with near-real-time storm data during severe weather events. Search for "GRLevel3 placefiles public" to find currently active sources. On a quiet weather day, you can use a static demonstration placefile to confirm the feature is working.

---

## Sonification

Sonification converts radar values into audio tones, allowing the radar data along a specific bearing to be heard rather than seen. This feature is designed for blind and low-vision users, but is useful for anyone who wants to understand radar without reading numbers.

### How sonification works

The app samples the radar data along a line extending from the radar site at a chosen bearing angle. Each range bin (roughly 5 km of distance) produces one tone. The tone's **frequency** encodes the radar value at that distance:

| Product | Low value (low pitch) | High value (high pitch) |
|---|---|---|
| Reflectivity (REF) | 0 dBZ → 200 Hz | 75 dBZ → 1600 Hz |
| Velocity (VEL) | −30 m/s → 220 Hz | +30 m/s → 1100 Hz |
| Diff. Reflectivity (ZDR) | −2 dB → 300 Hz | +5 dB → 900 Hz |
| Corr. Coefficient (RHO) | 0.70 → 200 Hz | 1.00 → 1200 Hz |

Each tone lasts 30 milliseconds with a smooth onset and release so consecutive tones do not click. The sequence covers the radar's range (up to 230 km) in about 1.4 seconds.

### Using the sonification control

The **Bearing** stepper in the Data Summary panel adjusts the bearing angle from 0° (north) to 359° in 5° steps. Click the stepper up or down to rotate the probe line. The sonification plays automatically each time the bearing changes.

Alongside the audio, the Data Summary panel shows text output listing the **top three echoes** by intensity — their strength and range — so the spoken result can be combined with the tones.

**Example output:** *"Strong echo: 52 dBZ at 85 km. Moderate: 38 dBZ at 140 km."*

### Interpreting the sounds

For Reflectivity, silence or low tones at the start of the sequence (the radar's near range) suggest clear skies nearby. A rising pitch at a certain point indicates precipitation beginning at that distance. A sequence of high-pitched tones sustained for several bins indicates a deep, intense storm cell. A brief high pitch followed by silence could be a thin line or a single storm cell.

> **Try it now:** Open the Data Summary panel and find the Sonification section. Set the bearing to 90° (due east). If there is precipitation east of the radar, you will hear rising pitches at the ranges where precipitation occurs. Rotate the bearing by 5° increments to scan around the compass, listening for where storms are strongest and closest.

---

## Accessibility Panel Reference

The Data Summary panel at the bottom of the window presents all data in plain text. It is organized into collapsible sections. Each section is a VoiceOver-navigable group.

| Section | Contents |
|---|---|
| **Radar** | Site, product, tilt, scan time (UTC), VCP, gate count and spacing |
| **Gate Probe** | Last clicked value, bearing, and range |
| **Animation** | Current frame number and scan time |
| **Sonification** | Bearing, top echo descriptions |
| **Alerts** | Count of active alerts; each alert's event name and expiration |
| **SPC Outlooks** | Highest risk category for Day 1, Day 2, Day 3 |
| **Mesoscale Discussions** | Count and text summary of each active MD |
| **Storm Reports** | Counts by type; details of each tornado, hail, and wind report |
| **Storm Cells** | Total tracked cells; per-cell bearing, range, and motion direction/speed (up to 5) |
| **Surface Observations** | Flight category summary; individual station data |
| **Model Layer** | Active model/product and forecast offset |
| **Satellite** | Active satellite channel and update time |
| **Placefiles** | Loaded placefiles; first 10 point labels |

**Live regions** in each section update automatically when data changes, triggering VoiceOver announcements. You do not need to navigate to a section to hear updates — they are announced as they occur.

---

## Settings and Preferences

Open Settings with **Cmd+,** or via the **wxaccess** menu.

### Radar Display

**Opacity** (30–100%, default 75%)
Controls how transparent the radar overlay is over the map.

**Image Resolution** (512 / 1024 / 2048 px, default 1024)
Higher resolution shows finer detail but takes slightly longer to render.

### Refresh

**Auto-Refresh** (toggle, default ON)
When on, wxaccess automatically loads the most recent radar scan on a regular interval.

**Refresh Interval** (2 / 5 / 10 minutes, default 5)
How often the app checks for new radar data. Most WSR-88D radars complete a full volume scan every 4.5–6 minutes, so 5 minutes is a practical minimum.

### Color Palette

**Palette** (NWS Standard / GRLevel3 Default / Colorblind-Friendly)
Sets the color table used to render radar data across all products.

### Range Rings

**Show Range Rings** (toggle, default OFF)
Draws concentric circles at 50, 100, 150, and 230 km from the radar site's location.

### Default Site

**Default Site** (picker, default KEWX)
The radar site loaded on every app launch.

### Placefiles

**Placefiles** (URL list)
Manage custom overlay URLs. Add via the text field; remove individually.

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Cmd+R` | Refresh — load the most recent radar scan now |
| `Cmd+L` | Toggle loop animation on/off |
| `Cmd+,` | Open Settings |
| `Tab` | Move focus to the next control |
| `Shift+Tab` | Move focus to the previous control |
| `Return` | Activate focused button or toggle |
| `Space` | Play/Pause animation (when animation controls are focused) |
| Arrow keys | Step through animation frames (when animation controls are focused) |

---

## Filing a Bug Report

The ladybug button at the right end of the toolbar lets you report a problem directly from within the app. When you submit a report, wxaccess automatically creates a GitHub issue on the wxaccess project page with a description of the problem and a snapshot of the app's internal state at the time of the report. You do not need a GitHub account to use this feature in general, but you do need one for the one-time setup described below.

### What gets included in a report

Every report contains three things:

- **Your description** — what you typed in the description field. The first line becomes the issue title.
- **App state snapshot** — the radar sites you had selected, the current product and tilt, which overlays were active, and any error message the app was showing at the time.
- **Recent log entries** — the last 50 lines written to the app's internal log in the five minutes before you submitted the report. These help diagnose network errors, data decoding problems, and other issues that do not produce a visible error message.

No personal information, location data, or radar imagery is included in the report.

### One-time setup: creating a GitHub token

wxaccess uses a GitHub personal access token to file issues on your behalf. You only need to do this once — the token is saved securely to your Mac's Keychain and reused automatically from then on.

**Step 1 — Sign in to GitHub**

Go to [github.com](https://github.com) in your browser and sign in to your account. If you do not have an account, create one for free at [github.com/signup](https://github.com/signup).

**Step 2 — Open the token creation page**

Click your profile photo in the top-right corner of any GitHub page. Choose **Settings** from the menu. In the left sidebar, scroll to the bottom and click **Developer settings**. Then click **Personal access tokens** → **Fine-grained tokens**.

**Step 3 — Generate a new token**

Click **Generate new token**. GitHub may ask you to confirm your password.

Fill in the form as follows:

| Field | What to enter |
|---|---|
| Token name | `wxaccess bug reporter` (or any name you will recognize) |
| Expiration | 1 year (or your preference) |
| Resource owner | Your GitHub username |
| Repository access | **Only select repositories**, then choose **wxaccess** from the list |

**Step 4 — Set the permission**

Under **Repository permissions**, find **Issues** in the list and change its access level to **Read and write**. All other permissions can remain set to **No access**.

**Step 5 — Generate and copy the token**

Click **Generate token** at the bottom of the page. GitHub will display your new token — a long string starting with `github_pat_`. **Copy it now.** GitHub will not show it again after you leave this page. If you lose it, you can always generate a new one by repeating these steps.

### Filing your first report

**Step 1** — Click the ladybug button in the toolbar (or choose **Help → File a Bug…** from the menu bar).

**Step 2** — The bug report sheet opens. Because this is your first time, a token entry field labeled **GitHub Personal Access Token** appears below the description field.

**Step 3** — Type a brief description of the problem in the main text area. For example: *"The radar image went blank after switching from KEWX to KHGX and never came back."* The clearer your description, the faster the problem can be diagnosed.

**Step 4** — Paste the token you copied from GitHub into the **GitHub Personal Access Token** field.

**Step 5** — Click **Submit**. The app files the issue, shows you a link to the newly created issue on GitHub, and saves the token to your Keychain.

After this first submission, the token field will not appear again. Future reports require only a description and a click of Submit.

### Subsequent reports

Click the ladybug button, type a description, and click **Submit**. That is all. The token is retrieved from your Keychain automatically.

### If submission fails

If the report cannot be filed, the sheet shows an error message and a **Try Again** button. Common causes:

| Error | What to do |
|---|---|
| "No GitHub token found" | The Keychain entry was deleted. Follow the one-time setup steps again. |
| "GitHub API error 401" | The token expired or was revoked. Generate a new one and paste it — the token field will reappear automatically. |
| "GitHub API error 403" | The token does not have Issues: Write permission on the wxaccess repository. Delete the token on GitHub, generate a new one, and make sure to select Issues → Read and write in Step 4 above. |
| Network error | Check your internet connection and try again. |

### Viewing filed reports

All filed reports appear at [github.com/w9fyi/wxaccess/issues](https://github.com/w9fyi/wxaccess/issues). You do not need to be signed in to view them. The **Open in Browser** button on the success screen takes you directly to the issue you just filed.

---

## Data Sources

All data used by wxaccess is free and requires no registration or API key.

| Source | URL | What is fetched |
|---|---|---|
| Unidata THREDDS (Level 2) | `thredds.ucar.edu` | Raw radar sweeps (Archive II format), 7-day rolling window |
| Unidata THREDDS (Level 3) | `thredds.ucar.edu` | Processed Level 3 products including NST storm cells, 14-day rolling window |
| NWS Alerts | `api.weather.gov` | Active watches, warnings, and advisories |
| Aviation Weather | `aviationweather.gov` | METAR surface observations |
| SPC | `spc.noaa.gov` | Convective outlooks, mesoscale discussions, storm reports |
| Iowa State Mesonet | `mesonet.agron.iastate.edu` | GOES-16 satellite tiles, HRRR/MRMS model tiles, county borders |

Data is fetched over HTTPS. No data is sent from your computer to any of these services — the app makes standard read-only HTTP requests identical to loading a webpage.

---

## About wxaccess

wxaccess is free and open-source software, licensed under the MIT License.

Copyright 2026 Justin Mann (AI5OS / @w9fyi)

Source code and issue tracker: [github.com/w9fyi/wxaccess](https://github.com/w9fyi/wxaccess)

Feedback and accessibility suggestions are welcome via GitHub Issues.
