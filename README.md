# wxaccess

VoiceOver-first NEXRAD weather radar viewer for macOS. A native Swift + MapKit alternative to GRLevel3 / RadarScope built around the principle that weather data should be fully accessible without touching the map canvas.

## Features

### Radar

- Live NEXRAD Level 2 from NOAA's public AWS S3 bucket — free, no API key
- All Level 2 dual-pol moments: reflectivity (REF), velocity (VEL), spectrum width (SW), differential reflectivity (ZDR), correlation coefficient (RHO), differential phase (PHI)
- NEXRAD Level 3 products: Super-Res Base Reflectivity (N0Q), Super-Res Velocity (N0U), Echo Tops (EET), Digital VIL (DVL), Storm Total Precip (STP), One-Hour Precip (OHP)
- Loop animation (up to 10 frames) with step controls and speed selection
- Click-to-probe: click any point on the map to read out the radar value, bearing, and range via VoiceOver announcement
- Five elevation tilt angles (0.5° – 4.3°)
- Archive date picker for historical scans
- Color palettes: NWS Standard, GRLevel3-style, Colorblind-friendly (blue-amber)
- Adjustable radar opacity and image resolution (512 / 1024 / 2048 px)

### Overlays

- Active NWS watches, warnings, and advisories with color-coded polygon overlays and full alert text
- SPC convective outlooks (Day 1, 2, 3) with categorical risk shading
- SPC mesoscale discussions with dashed polygon overlays
- SPC storm reports (tornado, hail, wind markers) updated continuously
- GOES-16 satellite tiles (visible, infrared, water vapor) via Iowa State Mesonet cache
- HRRR and MRMS model/analysis tiles via Iowa State Mesonet
- Surface observations (METAR flight category coloring: VFR/MVFR/IFR/LIFR)
- County borders, range rings (50/100/150/230 km)
- GRLevel3-compatible placefiles (AllisonHouse and custom URLs)

### Accessibility

- **Accessible data panel** — all radar metadata, alert details, gate probe results, SPC outlooks, storm reports, surface obs, and sonification output are fully readable by VoiceOver without touching the map canvas
- Live regions announce animation frame changes, probe results, and loading state
- Map canvas is marked `accessibilityHidden` — no focus traps in the visual overlay
- Sonification: tone-based encoding of radar values along a bearing (frequency maps to intensity)
- All toolbar controls and overlays labeled for VoiceOver

## All ~160 WSR-88D Sites

CONUS + Alaska, Hawaii, Puerto Rico, Guam.

## Requirements

- macOS 14.0+
- Xcode 16+

## Build

```sh
cd wxaccess
xcodegen generate
open wxaccess.xcodeproj
```

## Data Sources

All free, no account or API key required:

| Source | Data |
| --- | --- |
| `noaa-nexrad-level2.s3.amazonaws.com` | NEXRAD Level 2 (real-time + archive) |
| `unidata-nexrad-level3.s3.amazonaws.com` | NEXRAD Level 3 products |
| `api.weather.gov` | NWS alerts |
| `aviationweather.gov` | METAR surface observations |
| `spc.noaa.gov` | Convective outlooks, mesoscale discussions, storm reports |
| `mesonet.agron.iastate.edu` | GOES-16 satellite tiles, HRRR/MRMS model tiles, county borders |

## Architecture

```text
NEXRAD/    — Level 2 fetcher (NOAA S3), Archive II decoder + bzip2; Level 3 fetcher (Unidata S3), Packet Code 16 decoder
NWS/       — Alerts fetcher (api.weather.gov), METAR surface obs (aviationweather.gov)
SPC/       — Convective outlooks, mesoscale discussions, storm reports
Placefile/ — GRLevel3-compatible placefile parser and fetcher
Map/       — MKMapView wrapper, radar/Level3/alert/SPC/satellite overlays, range rings, annotations
Audio/     — Sonification engine (AVAudioEngine tone synthesis)
GOES/      — GOES-16 satellite tile overlay
Model/     — HRRR/MRMS model tile overlay
UI/        — SiteSelector, AlertsList, AccessibilityPanel (VoiceOver live regions)
```

## License

MIT — © 2026 Justin Mann (AI5OS / @w9fyi)
