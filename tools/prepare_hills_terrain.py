#!/usr/bin/env python3
"""ARCHIVED: not consumed by the GPXZ-only iOS runtime.

Prepare genuine, locally acquired Hills DEMs; never fetch data or credentials.

See TERRAIN_PREPARATION.md for required public provenance inputs. Output heights
retain the provider's vertical datum: only the horizontal coordinates are warped.
"""

from __future__ import annotations

import argparse
from contextlib import ExitStack
from datetime import date
import hashlib
import json
import math
from pathlib import Path
import tempfile
from urllib.parse import urlsplit

import numpy as np
from pyproj import CRS, Transformer
import rasterio
from rasterio.merge import merge
from rasterio.transform import Affine
from rasterio.warp import Resampling, reproject, transform_bounds


RADIUS = 6_371_000.0
MAX_CELLS = 16_000_000
MAX_DIMENSION = 16_384
DATA_FILE = "hills-terrain-v1.f32"
MANIFEST_FILE = "hills-terrain-v1.json"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "fairwayvector-pintheory/Resources/Terrain"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def local_file(value: str) -> Path:
    # Reject GDAL virtual paths and network URLs before handing anything to GDAL.
    require("://" not in value and not value.startswith("/vsi"), "Local files only.")
    path = Path(value).expanduser().resolve(strict=True)
    require(path.is_file(), "Input must be a regular local file.")
    return path


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    require(isinstance(value, dict), "Expected a JSON object.")
    return value


def public_url(value: str, host: str | None = None) -> str:
    parsed = urlsplit(value)
    require(parsed.scheme == "https" and bool(parsed.hostname), "Expected public HTTPS provenance URL.")
    require(not parsed.username and not parsed.password and not parsed.query,
            "Provenance URLs must not contain credentials or query parameters.")
    if host:
        require(parsed.hostname == host or parsed.hostname.endswith("." + host),
                "Provenance URL must identify the expected public provider.")
    return value


def grid_geometry(bounds: list[float], buffer: float) -> dict:
    west, south, east, north = bounds
    require(all(math.isfinite(v) for v in bounds) and -180 < west < east < 180
            and -89 < south < north < 89, "Invalid lon/lat bounds.")
    require(math.isfinite(buffer) and buffer >= 0, "Buffer must be finite and nonnegative.")
    lat, lon = (south + north) / 2, (west + east) / 2
    proj = f"+proj=eqc +lat_ts={lat} +lat_0={lat} +lon_0={lon} +R={RADIUS} +units=m"
    crs = CRS.from_proj4(proj)
    forward = Transformer.from_crs(4326, crs, always_xy=True)
    inverse = Transformer.from_crs(crs, 4326, always_xy=True)
    left, bottom = forward.transform(west, south)
    right, top = forward.transform(east, north)
    # Align CELL CENTERS outwards, so contains() includes the entire buffered bbox.
    x, y = math.floor(left - buffer), math.ceil(top + buffer)
    width = math.ceil(right + buffer) - x + 1
    height = y - math.floor(bottom - buffer) + 1
    require(width <= MAX_DIMENSION and height <= MAX_DIMENSION and width * height <= MAX_CELLS,
            "Terrain exceeds the engine's dimension / 16M-cell limits.")
    references = [(west, south), (west, north), (east, south), (east, north), (lon, lat)]
    error = 0.0
    inverse_error = 0.0
    for p_lon, p_lat in references:
        px, py = forward.transform(p_lon, p_lat)
        sx = math.radians(p_lon - lon) * RADIUS * math.cos(math.radians(lat))
        sy = math.radians(p_lat - lat) * RADIUS
        error = max(error, abs(px - sx), abs(py - sy))
        back_lon, back_lat = inverse.transform(sx, sy)
        inverse_error = max(inverse_error, abs(back_lon - p_lon), abs(back_lat - p_lat))
    require(error < 1e-7 and inverse_error < 1e-10, "Swift spherical EQC / PROJ mismatch.")
    return {"crs": crs, "proj": proj, "lat": lat, "lon": lon, "x": x, "y": y,
            "width": width, "height": height,
            "transform": Affine(1, 0, x - 0.5, 0, -1, y + 0.5),
            "projectionErrorMeters": error, "inverseErrorDegrees": inverse_error}


def source_inventory(args: argparse.Namespace, datasets: list) -> tuple[list[dict], str]:
    collection = read_json(args.collection)
    require(collection.get("license") == "CC-BY-4.0", "Provider collection must confirm CC-BY-4.0.")
    catalog = read_json(args.stac_items)
    items = catalog.get("features", [catalog] if catalog.get("type") == "Feature" else [])
    by_name = {Path(urlsplit(i["assets"]["data"]["href"]).path).name: i for i in items}
    require(len(args.survey_metadata) == len(datasets), "One ursprung metadata file is required per COG.")
    evidence = read_json(args.datum_evidence)
    require(evidence.get("verticalDatum") == "RH2000", "Hills pilot requires verified RH2000 evidence.")
    public_url(evidence["url"], "lantmateriet.se")
    require("RH2000" in evidence["statement"].replace(" ", ""),
            "Evidence must quote a provider statement naming RH2000; do not infer it.")
    source_dates: list[str] = []
    records = []
    for path, dataset, survey_path in zip(args.sources, datasets, args.survey_metadata):
        require(path.name in by_name, "Local COG filename does not match a supplied STAC asset.")
        item = by_name[path.name]
        require(item.get("collection") == collection["id"], "STAC collection mismatch.")
        asset, props = item["assets"]["data"], item["properties"]
        require(props.get("geometriskupplosning") == 1, "STAC must declare actual 1m source resolution.")
        declared = CRS.from_user_input(asset.get("proj:epsg") or props.get("proj:code") or props["proj:epsg"])
        horizontal = declared.sub_crs_list[0] if declared.is_compound else declared
        require(declared.to_epsg() == 5845, "Expected provider SWEREF99 TM + RH2000 declaration (EPSG:5845).")
        require(dataset.crs is not None, "Raster CRS is missing.")
        actual = CRS.from_user_input(dataset.crs)
        actual_horizontal = actual.sub_crs_list[0] if actual.is_compound else actual
        require(actual_horizontal.equals(horizontal), "Raster CRS differs from STAC horizontal CRS.")
        if actual.is_compound:
            require(actual.equals(declared), "Raster vertical CRS differs from provider declaration.")
        require(dataset.driver == "GTiff", "Source must be a real GeoTIFF, not an indirect virtual raster.")
        require(dataset.count == 1 and dataset.dtypes[0] == "float32", "Expected one Float32 elevation band.")
        require(dataset.scales == (1.0,) and dataset.offsets == (0.0,), "Scaled heights are unsupported.")
        require(dataset.units[0] in (None, "m", "metre", "meter"), "Elevation units are not metres.")
        t = dataset.transform
        require(abs(t.a - 1) < 1e-9 and abs(t.e + 1) < 1e-9 and t.b == 0 and t.d == 0,
                "Actual raster must be north-up, unrotated, 1m spacing.")
        require(all(axis.unit_name == "metre" for axis in actual_horizontal.axis_info), "CRS units must be metres.")
        require(asset.get("proj:shape") == [dataset.height, dataset.width], "STAC / raster dimensions differ.")
        require(np.allclose(asset["proj:bbox"], tuple(dataset.bounds), rtol=0, atol=1e-6),
                "STAC / raster native extents differ.")
        require(path.stat().st_size == asset["file:size"], "Original COG byte size differs from STAC.")
        require(survey_path.name == Path(urlsplit(item["assets"]["metadata"]["href"]).path).name,
                "Survey metadata filename does not match this STAC item.")
        dates = sorted({f["properties"]["matdatum"] for f in read_json(survey_path)["features"]})
        require(bool(dates), "Survey metadata contains no observed matdatum dates.")
        for observed in dates:
            date.fromisoformat(observed)
        require(min(dates) == props["start_datetime"][:10] and max(dates) == props["end_datetime"][:10],
            "Observed survey metadata range differs from STAC; investigate missing or stale metadata.")
        # Conservative FULL SOURCE TILE range; do not claim a uniform crop survey date.
        source_dates.extend(dates)
        item_url = next(link["href"] for link in item["links"] if link["rel"] == "self")
        records.append({"id": item["id"], "itemURL": public_url(item_url, "lantmateriet.se"),
                        "assetURL": public_url(asset["href"], "lantmateriet.se"),
                        "metadataURL": public_url(item["assets"]["metadata"]["href"], "lantmateriet.se"),
                        "sourceCRS": actual.to_string(), "declaredCRS": declared.to_string(),
                        "sourceBounds": list(dataset.bounds), "sourceResolutionMeters": list(dataset.res),
                        "sourceBytes": path.stat().st_size, "surveyDates": dates,
                        "rasterDriver": dataset.driver, "rasterUnits": dataset.units[0],
                        "rasterLayout": dataset.tags(ns="IMAGE_STRUCTURE").get("LAYOUT"),
                        "nodata": str(dataset.nodata), "verticalDatumEncodedInRaster": actual.is_compound})
    low, high = min(source_dates), max(source_dates)
    return records, low if low == high else f"{low}/{high}"


def verify_heights(grid: np.ndarray, mosaic: np.ndarray, source_transform: Affine,
                   source_crs: CRS, geometry: dict) -> dict:
    """Compare output CELL CENTER heights with independent source bilinear values."""
    to_source = Transformer.from_crs(geometry["crs"], source_crs, always_xy=True)
    checked = 0
    maximum = 0.0
    points = []
    for row in np.linspace(0, grid.shape[0] - 1, 7, dtype=int):
        for col in np.linspace(0, grid.shape[1] - 1, 7, dtype=int):
            x, y = geometry["transform"] * (int(col) + 0.5, int(row) + 0.5)
            sx, sy = to_source.transform(x, y)
            sc, sr = (~source_transform) * (sx, sy)
            sc, sr = sc - 0.5, sr - 0.5
            c, r = math.floor(sc), math.floor(sr)
            if not (0 <= r < mosaic.shape[0] - 1 and 0 <= c < mosaic.shape[1] - 1):
                continue
            patch = mosaic[r:r + 2, c:c + 2].astype(np.float64)
            if not np.isfinite(patch).all() or not math.isfinite(float(grid[row, col])):
                continue
            fx, fy = sc - c, sr - r
            expected = float(patch[0, 0] * (1 - fx) * (1 - fy) + patch[0, 1] * fx * (1 - fy)
                             + patch[1, 0] * (1 - fx) * fy + patch[1, 1] * fx * fy)
            delta = abs(expected - float(grid[row, col]))
            maximum = max(maximum, delta)
            checked += 1
            points.append({"column": int(col), "row": int(row), "sourceHeight": expected,
                           "outputHeight": float(grid[row, col]), "errorMeters": delta})
    require(checked >= 5 and maximum < 0.02, "Insufficient source height agreement (<2cm, >=5 references required).")
    return {"checkedCellCenters": checked, "maxErrorMeters": maximum, "references": points}


def prepare(args: argparse.Namespace) -> dict:
    geometry = grid_geometry(args.bounds, args.buffer_meters)
    public_url(args.bounds_source)
    args.output = args.output.expanduser().resolve()
    targets = [args.output / name for name in (DATA_FILE, MANIFEST_FILE, "hills-preparation-report.json")]
    require(args.overwrite or not any(p.exists() for p in targets), "Output exists; use --overwrite explicitly.")
    with ExitStack() as stack:
        datasets = [stack.enter_context(rasterio.open(path)) for path in args.sources]
        records, source_date = source_inventory(args, datasets)
        source_crs = CRS.from_user_input(datasets[0].crs)
        if source_crs.is_compound:
            source_crs = source_crs.sub_crs_list[0]
        require(all(d.crs == datasets[0].crs for d in datasets), "COGs must have the same CRS.")
        t = geometry["transform"]
        left, top = t * (0, 0)
        right, bottom = t * (geometry["width"], geometry["height"])
        native = transform_bounds(geometry["crs"], source_crs, left, bottom, right, top, densify_pts=41)
        crop = (math.floor(native[0]) - 3, math.floor(native[1]) - 3,
                math.ceil(native[2]) + 3, math.ceil(native[3]) + 3)
        require((crop[2] - crop[0]) * (crop[3] - crop[1]) <= MAX_CELLS * 2,
                "Native mosaic is too large; no national DEM processing is allowed.")
        # Mosaic BEFORE warping: bilinear interpolation can cross original tile seams.
        merged, source_transform = merge(datasets, bounds=crop, res=1, nodata=np.nan,
                                         dtype="float32", indexes=[1], method="first")
        mosaic = merged[0]
        mosaic[~np.isfinite(mosaic)] = np.nan
        grid = np.full((geometry["height"], geometry["width"]), np.nan, dtype=np.float32)
        reproject(mosaic, grid, src_transform=source_transform, src_crs=source_crs,
                  src_nodata=np.nan, dst_transform=t, dst_crs=geometry["crs"], dst_nodata=np.nan,
                  resampling=Resampling.bilinear, num_threads=1, ERROR_THRESHOLD=0.0)
        grid[~np.isfinite(grid)] = np.nan
        nodata_count = int(np.count_nonzero(~np.isfinite(grid)))
        require(nodata_count == 0 or args.allow_nodata, "Crop has NoData; supply missing tiles or explicitly --allow-nodata.")
        height_verification = verify_heights(grid, mosaic, source_transform, source_crs, geometry)
    manifest = {"schemaVersion": 1, "id": "hills-sweden", "courseName": "Hills Golf & Country Club",
                "source": "Lantmäteriet Markhöjdmodell Nedladdning; bilinear horizontal reprojection",
                "sourceURL": public_url(next(link["href"] for link in read_json(args.collection)["links"]
                                              if link["rel"] == "self"), "lantmateriet.se"),
                "license": "CC-BY-4.0", "sourceDate": source_date, "verticalDatum": "RH2000",
                "sourceResolutionMeters": 1, "gridResolutionMeters": 1,
                "projectionOrigin": {"lat": geometry["lat"], "lon": geometry["lon"]},
                "originX": geometry["x"], "originY": geometry["y"], "width": geometry["width"],
                "height": geometry["height"], "dataFile": DATA_FILE}
    report = {"courseBounds": args.bounds, "boundsSource": args.bounds_source,
              "bufferMeters": args.buffer_meters, "projection": geometry["proj"],
              "projectionErrorMeters": geometry["projectionErrorMeters"],
              "inverseErrorDegrees": geometry["inverseErrorDegrees"],
              "verticalDatumEvidence": read_json(args.datum_evidence),
              "sourceDateScope": "Conservative survey date range across complete input tiles, not uniform crop age",
              "sources": records, "nodataCells": nodata_count, "finiteCells": int(grid.size) - nodata_count,
              "sourceHeightVerification": height_verification}
    # Validation completes before publishing. Manifest is replaced LAST; a failed
    # interrupted replacement is detectable by the engine's mandatory SHA256.
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".hills-preparation-", dir=args.output) as temporary:
        staged = Path(temporary)
        binary = staged / DATA_FILE
        grid.astype("<f4", copy=False).tofile(binary)
        expected_bytes = geometry["width"] * geometry["height"] * 4
        require(binary.stat().st_size == expected_bytes, "Unexpected Float32 output size.")
        manifest["sha256"] = hashlib.sha256(binary.read_bytes()).hexdigest()
        report["outputBytes"] = expected_bytes
        report["sha256"] = manifest["sha256"]
        encoded = json.dumps(manifest, ensure_ascii=False, indent=2, allow_nan=False) + "\n"
        require(len(encoded.encode("utf-8")) <= 65_536, "Manifest exceeds engine limit.")
        (staged / MANIFEST_FILE).write_text(encoded, encoding="utf-8")
        (staged / targets[2].name).write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False)
                                            + "\n", encoding="utf-8")
        for target in (targets[0], targets[2], targets[1]):
            (staged / target.name).replace(target)
    return {"width": geometry["width"], "height": geometry["height"], "bytes": expected_bytes,
            "sourceDate": source_date, "verticalDatum": "RH2000", "sha256": manifest["sha256"],
            "nodataCells": nodata_count, "sourceHeightMaxErrorMeters": height_verification["maxErrorMeters"]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sources", nargs="+", type=local_file, help="Original local COG(s), provider filenames retained")
    parser.add_argument("--bounds", nargs=4, type=float, required=True, metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    parser.add_argument("--bounds-source", required=True, help="Public source identifying the verified course bbox")
    parser.add_argument("--buffer-meters", type=float, default=200)
    parser.add_argument("--stac-items", type=local_file, required=True, help="Saved STAC item / FeatureCollection")
    parser.add_argument("--collection", type=local_file, required=True, help="Saved provider STAC collection")
    parser.add_argument("--survey-metadata", nargs="+", type=local_file, required=True,
                        help="Original ursprung JSONs in the same order as COGs")
    parser.add_argument("--datum-evidence", type=local_file, required=True, help="Verified provider datum documentation JSON")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--allow-nodata", action="store_true", help="Explicitly permit partial NaN coverage")
    parser.add_argument("--overwrite", action="store_true")
    args = parser.parse_args()
    try:
        print(json.dumps(prepare(args), ensure_ascii=False, indent=2))
    except (ValueError, KeyError, StopIteration, OSError, rasterio.errors.RasterioError) as error:
        # No raster tags, environment, credentials, or source content are printed.
        reason = str(error) if isinstance(error, ValueError) else type(error).__name__
        parser.exit(1, f"Preparation failed: {reason}. No new valid package published.\n")


if __name__ == "__main__":
    main()