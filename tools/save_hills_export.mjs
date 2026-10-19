// Offline packaging of ONLY the five explicitly authorized, already-staged JSON files.
// No transport, secrets, preferences, ledger, or unrelated sandbox access.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';

const source = process.argv[2];
assert(source, 'Provide the existing staged export directory.');
const id = '0121161534832877';
const geometryName = `course-${id}-hills-golf---sports-club-hills-62-male-golfapi-v1.json`;
const names = [`CourseData/${geometryName}`, 'CourseData/terrain-gpxz-v1.json',
  `GolfAPI/course-${id}-detail.json`, `GolfAPI/course-${id}-coordinates.json`, 'GolfAPI/search-sweden--hills.json'];
const bytes = names.map(name => fs.readFileSync(path.join(source, name)));
const [geometry, terrain, detail, coordinates, search] = bytes.map(data => JSON.parse(data));
const hash = data => crypto.createHash('sha256').update(data).digest('hex');
assert.equal(hash(`golfapi:${id}`), '6916666b421f2b3d096d83384e1e00cf84b22653557eed017a4c22ed27ee091a');
assert.equal(geometry.golfAPICourseID, id);
assert.equal(detail.courseID, id);
assert.equal(coordinates.courseID, id);
assert.equal(terrain.courseID, `golfapi:${id}`);
assert.equal(terrain.schemaVersion, 1);
assert.equal(+detail.numHoles, 18);
assert.equal(geometry.holes.length, 18);
assert.equal(coordinates.coordinates.length, 121);
const tee = detail.tees.find(t => t.teeID === '185072' && t.teeName === '62');
assert(tee && tee.courseRatingMen === 74.7 && tee.slopeMen === 140);
for (const hole of geometry.holes) {
  const points = coordinates.coordinates.filter(p => +p.hole === hole.number);
  const front = points.find(p => +p.poi === 11), back = points.find(p => +p.poi === 12);
  const green = points.find(p => +p.poi === 1 && +p.location === 2);
  assert(front && back && green);
  assert(Math.abs(hole.path[0].lat - (+front.latitude + +back.latitude) / 2) < 1e-10);
  assert(Math.abs(hole.path[0].lon - (+front.longitude + +back.longitude) / 2) < 1e-10);
  assert.equal(hole.path[1].lat, +green.latitude);
  assert.equal(hole.path[1].lon, +green.longitude);
  assert.equal(hole.measuredLengthMeters, tee[`length${hole.number}`]);
}
// Conservative privacy boundary: do NOT infer public provenance from arbitrary map targets.
// Every original path vertex must coincide with a public hole endpoint, and lie on that hole.
const vector = (p, a) => [(p.lon - a.lon) * Math.PI / 180 * 6371000 * Math.cos(a.lat * Math.PI / 180),
  (p.lat - a.lat) * Math.PI / 180 * 6371000];
const distance = (a, b) => Math.hypot(...vector(b, a));
const onSegment = (p, a, b) => {
  const x = vector(p, a), v = vector(b, a), vv = v[0] ** 2 + v[1] ** 2;
  const t = (x[0] * v[0] + x[1] * v[1]) / vv;
  return t >= -1e-8 && t <= 1 + 1e-8 && Math.hypot(x[0] - t * v[0], x[1] - t * v[1]) <= .02;
};
const safe = terrain.responses.filter(record => geometry.holes.some(hole => record.path.every(p =>
  hole.path.some(q => distance(p, q) <= .02) && onSegment(p, hole.path[0], hole.path.at(-1)))));
// This export contains no provably public whole-path records. Never package clicked/GPS paths.
assert.equal(safe.length, 0, 'Re-review a changed terrain export before packaging any terrain.');
const backup = path.resolve('exports/hills-iphone-2026-10-05');
const output = path.resolve('fairwayvector-pintheory/Resources/SavedCourses/Hills');
assert(!fs.existsSync(backup) && !fs.existsSync(output), 'Refuse to overwrite an existing export/resource.');
names.forEach((name, i) => {
  const file = path.join(backup, name);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, bytes[i], { flag: 'wx', mode: 0o600 });
});
fs.mkdirSync(output, { recursive: true });
delete detail.apiRequestsLeft;
delete coordinates.apiRequestsLeft;
const clubs = search.clubs.filter(club => club.clubID === detail.clubID).map(club => ({ ...club,
  courses: club.courses.filter(course => course.courseID === id) }));
assert.equal(clubs.length, 1);
assert.equal(clubs[0].courses.length, 1);
const resources = {
  [geometryName]: bytes[0],
  [`course-${id}-detail.json`]: Buffer.from(JSON.stringify(detail, null, 2) + '\n'),
  [`course-${id}-coordinates.json`]: Buffer.from(JSON.stringify(coordinates, null, 2) + '\n'),
  'hills-club.json': Buffer.from(JSON.stringify({ clubs }, null, 2) + '\n')
};
for (const [name, data] of Object.entries(resources)) fs.writeFileSync(path.join(output, name), data, { flag: 'wx' });
const manifest = { schemaVersion: 1, courseID: id, clubID: detail.clubID, defaultTeeID: tee.teeID,
  defaultTeeName: tee.teeName, defaultSex: 'male', holes: 18, coordinates: 121,
  use: 'Internal development only; verify Golf API, GPXZ and source licences before any public distribution.',
  terrain: { bundledResponses: 0, localResponses: terrain.responses.length,
    localSamples: terrain.responses.reduce((n, r) => n + r.samples.length, 0),
    reason: 'No whole original path verifiable as public hole endpoints; captured origins/targets remain ignored locally.' },
  resources: Object.entries(resources).map(([name, data]) => ({ name, bytes: data.length, sha256: hash(data) })),
  originals: names.map((name, i) => ({ name, bytes: bytes[i].length, sha256: hash(bytes[i]) })) };
fs.writeFileSync(path.join(output, 'hills-manifest.json'), JSON.stringify(manifest, null, 2) + '\n', { flag: 'wx' });
console.log(JSON.stringify({ bundledFiles: 5, backupFiles: 5, ...manifest.terrain, sourceResolutionMeters:
  [...new Set(terrain.responses.flatMap(r => r.samples.flatMap(s => s.provenance.map(p => p.resolutionMeters))))] }, null, 2));