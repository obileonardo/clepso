/* The footer village (founder request, 17 Oct 2026, after Corgi's painted footer on Mobbin, 12.13): coding agents
   living together around the Clepso tower. A voxel diorama in Three.js, rendered at a low resolution and scaled up so it
   reads as pixel art. Only agents Clepso can read today add to the tower's glow; the rest bring tokens Clepso can't read
   yet, which fall back grey. Statuses come from the page (build-site.py VILLAGE), never from here.
   Loaded on demand by site.js when the footer comes near; respects Reduce Motion (one still frame, redrawn on input). */
import * as THREE from "./vendor/three.module.min.js";

const C = {
  grass: [0x16341f, 0x1a3b24, 0x133020], hill: [0x102a19, 0x0e2416, 0x13301d], road: 0x5a5140, plaza: 0x34443a, soil: 0x22190f,
  water: 0x12424e, wall: 0xd8d1bc, door: 0x2a2119, glow: 0xffc04d, trunk: 0x4a3424, leaves: [0x1f6b3a, 0x27804a, 0x1a5c33],
  stone: 0x24342b, accent: 0x4dff8f, cream: 0xf3f1e7, dark: 0x0b120e, grey: 0x7d8a82,
};
const W0 = -32, W1 = 32, D0 = -8, D1 = 6;          // ground extent (x, z)
const ROAD_Z = 1, HOUSE_Z = -4.5, TOWER = new THREE.Vector3(0, 0, -3.5);
const SLOTS = [-27, -20, -13, -6.5, 6.5, 13, 20, 27];

export function start(root) {
  const data = JSON.parse(root.querySelector("#village-data")?.textContent || "[]");
  const stage = root.querySelector(".village-stage"), canvas = stage.querySelector("canvas");
  const card = root.querySelector(".village-card"), label = root.querySelector(".village-label");
  const roster = [...root.querySelectorAll("[data-agent]")];
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  let renderer;
  try { renderer = new THREE.WebGLRenderer({ canvas, antialias: false, alpha: true, powerPreference: "low-power" }); }
  catch { root.classList.add("no-3d"); return; }
  renderer.setPixelRatio(1);
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.BasicShadowMap;
  const scene = new THREE.Scene();
  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
  const rand = mulberry(17);

  // ---------------------------------------------------------------------------------------------------- light
  scene.add(new THREE.HemisphereLight(0xf1f4ff, 0x1a2a1f, 1.5));
  const moon = new THREE.DirectionalLight(0xfff6e8, 1.7);
  moon.position.set(-18, 30, 16); moon.castShadow = true;
  Object.assign(moon.shadow.camera, { left: -40, right: 40, top: 20, bottom: -20, near: 1, far: 90 });
  moon.shadow.mapSize.set(1024, 512);
  scene.add(moon);
  const beacon = new THREE.PointLight(C.accent, 40, 22, 1.4);
  beacon.position.set(TOWER.x, 7, TOWER.z + 0.5);
  scene.add(beacon);

  const box = new THREE.BoxGeometry(1, 1, 1);
  const mats = new Map();
  const mat = (color, emissive = 0) => {
    const key = color + ":" + emissive;
    if (!mats.has(key)) mats.set(key, new THREE.MeshLambertMaterial({ color, emissive: emissive ? color : 0, emissiveIntensity: emissive }));
    return mats.get(key);
  };
  const cube = (parent, color, sx, sy, sz, x, y, z, emissive = 0, shadows = true) => {
    const m = new THREE.Mesh(box, mat(color, emissive));
    m.scale.set(sx, sy, sz); m.position.set(x, y, z);
    m.castShadow = shadows; m.receiveShadow = shadows;
    parent.add(m); return m;
  };

  // --------------------------------------------------------------------------------------------------- ground
  const lane = x => SLOTS.some(s => Math.abs(x - s) < 0.6);
  const tiles = [];
  for (let x = W0; x < W1; x++) for (let z = D0; z < D1; z++) {
    const cx = x + 0.5, cz = z + 0.5;
    let color = C.grass[(x * 7 + z * 13) & 1 ? 0 : (x + z) % 3 === 0 ? 2 : 1], h = 1;
    if (z === ROAD_Z) color = C.road;
    else if (z >= -2 && z < ROAD_Z && lane(cx)) color = C.road;
    else if (Math.abs(cx) < 4.5 && z >= -2 && z < ROAD_Z) color = C.plaza;
    else if (cx > 15 && cx < 24 && z >= 3 && z <= 4) { color = C.water; h = 0.75; }
    else if (z <= -7) { h = 1 + Math.round(1.6 + Math.sin(x * 0.35) * 1.2 + Math.sin(x * 0.9 + 1) * 0.6); color = C.hill[(x + z) % 3 & 3] || C.hill[0]; }
    tiles.push([cx, cz, h, color]);
  }
  const ground = new THREE.InstancedMesh(box, new THREE.MeshLambertMaterial(), tiles.length);
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), col = new THREE.Color();
  tiles.forEach(([x, z, h, color], i) => {
    m4.compose(new THREE.Vector3(x, (h - 2) / 2, z), q, new THREE.Vector3(1, h, 1));
    ground.setMatrixAt(i, m4); ground.setColorAt(i, col.set(color));
  });
  ground.receiveShadow = true;
  scene.add(ground);
  cube(scene, C.soil, W1 - W0, 2, D1 - D0, 0, -2, (D0 + D1) / 2, 0, false);

  // ----------------------------------------------------------------------------------------- tower (Clepso)
  const tower = new THREE.Group(); tower.position.copy(TOWER); scene.add(tower);
  cube(tower, C.stone, 4, 0.6, 4, 0, 0.3, 0);
  cube(tower, 0x1c2b23, 1.8, 5.2, 1.8, 0, 3.2, 0);
  [1.6, 2.8, 4, 5.2].forEach(y => cube(tower, C.accent, 1.95, 0.14, 1.95, 0, y, 0, 0.5, false));
  const core = cube(tower, C.accent, 1.3, 1.3, 1.3, 0, 6.6, 0, 1.2, false);
  const towerHit = cube(tower, 0, 4, 8, 4, 0, 4, 0, 0, false); towerHit.material = hitMat(); towerHit.userData.kind = "tower";

  // -------------------------------------------------------------------------------------------- houses
  const hits = [towerHit];
  const homes = new Map();
  SLOTS.forEach((x, i) => {
    const a = data[i];
    const g = new THREE.Group(); g.position.set(x, 0, HOUSE_Z); scene.add(g);
    if (!a) {                                                    // the empty plot: scaffolding for the next agent
      [[-1.3, -1], [1.3, -1], [-1.3, 1], [1.3, 1]].forEach(([px, pz]) => cube(g, C.trunk, 0.18, 2.6, 0.18, px, 1.3, pz));
      cube(g, C.trunk, 2.9, 0.15, 0.2, 0, 2.4, 1); cube(g, C.trunk, 2.9, 0.15, 0.2, 0, 1.2, 1);
      cube(g, C.grey, 0.9, 0.9, 0.9, -0.6, 0.45, 0.2); cube(g, C.grey, 0.9, 0.9, 0.9, 0.5, 0.45, -0.3); cube(g, C.grey, 0.8, 0.8, 0.8, 0, 1.25, 0);
      cube(g, C.cream, 0.08, 1, 0.08, 1.9, 0.5, 1.7); cube(g, C.cream, 0.9, 0.55, 0.08, 1.9, 1.15, 1.72);
      const hit = cube(g, 0, 4, 4, 4, 0, 2, 0, 0, false); hit.material = hitMat(); hit.userData.kind = "plot"; hits.push(hit);
      return;
    }
    cube(g, C.wall, 3.2, 2.2, 2.8, 0, 1.1, 0);
    cube(g, a.color, 3.7, 0.55, 3.3, 0, 2.47, 0, 0.18);
    cube(g, a.color, 2.7, 0.55, 2.4, 0, 3.0, 0, 0.18);
    cube(g, a.color, 1.5, 0.5, 1.3, 0, 3.5, 0, 0.18);
    cube(g, C.door, 0.8, 1.3, 0.1, 0, 0.65, 1.42, 0, false);
    const lit = a.status === "today" ? 0.9 : 0.55;
    cube(g, C.glow, 0.55, 0.5, 0.06, -1, 1.35, 1.42, lit, false); cube(g, C.glow, 0.55, 0.5, 0.06, 1, 1.35, 1.42, lit, false);
    cube(g, C.glow, 0.06, 0.5, 0.55, 1.62, 1.35, 0, lit * 0.8, false);
    if (i % 2) cube(g, C.stone, 0.45, 1.1, 0.45, 1, 3.4, -0.6);
    homes.set(a.id, x);
  });

  // ------------------------------------------------------------------------------------- trees, lamps, sky
  const hillTop = x => z => z <= -7 ? 1 + Math.round(1.6 + Math.sin((x - 0.5) * 0.35) * 1.2 + Math.sin((x - 0.5) * 0.9 + 1) * 0.6) - 1 : 0;
  const nearHouse = x => SLOTS.some(s => Math.abs(x - s) < 2.6);
  for (let n = 0, tries = 0; n < 34 && tries < 900; tries++) {
    const x = Math.floor(W0 + 1 + rand() * (W1 - W0 - 2)) + 0.5, z = Math.floor(D0 + rand() * 4);   // z -8 … -5
    if ((nearHouse(x) && z >= -7) || (Math.abs(x) < 3 && z >= -6)) continue;
    const t = new THREE.Group(); t.position.set(x, hillTop(x)(z), z + 0.5); scene.add(t);
    const s = 0.8 + rand() * 0.6;
    cube(t, C.trunk, 0.35, 1 * s, 0.35, 0, 0.5 * s, 0);
    cube(t, C.leaves[n % 3], 1.5 * s, 1.2 * s, 1.5 * s, 0, 1.4 * s, 0);
    cube(t, C.leaves[(n + 1) % 3], 0.9 * s, 0.8 * s, 0.9 * s, 0, 2.3 * s, 0);
    n++;
  }
  for (let n = 0, tries = 0; n < 26 && tries < 600; tries++) {                                       // bushes and flowers in front
    const x = Math.floor(W0 + 1 + rand() * (W1 - W0 - 2)) + 0.5, z = 3 + Math.floor(rand() * 3);
    if ((x > 14 && x < 25 && z <= 4) || (Math.abs(x) < 1)) continue;
    const big = rand() < 0.6;
    cube(scene, C.leaves[n % 3], big ? 0.9 : 0.5, big ? 0.6 : 0.35, big ? 0.9 : 0.5, x, big ? 0.3 : 0.18, z + 0.5);
    if (!big) cube(scene, [C.glow, 0xff8a5b, C.cream][n % 3], 0.18, 0.18, 0.18, x, 0.42, z + 0.5, 0.4, false);
    n++;
  }
  for (let x = W0 + 3.5; x < W1 - 2; x += 7) {
    if (Math.abs(x) < 5) continue;
    cube(scene, C.stone, 0.14, 1.5, 0.14, x, 0.75, ROAD_Z + 1.2);
    cube(scene, C.glow, 0.32, 0.32, 0.32, x, 1.6, ROAD_Z + 1.2, 1.4, false);
  }
  const stars = new THREE.BufferGeometry(), sp = [];
  for (let i = 0; i < 160; i++) sp.push(W0 * 1.6 + rand() * (W1 - W0) * 1.6, 9 + rand() * 16, -26 - rand() * 10);
  stars.setAttribute("position", new THREE.Float32BufferAttribute(sp, 3));
  const starMat = new THREE.PointsMaterial({ color: 0xcfe3ff, size: 1, sizeAttenuation: false, transparent: true, opacity: 0.8 });
  scene.add(new THREE.Points(stars, starMat));
  const flyGeo = new THREE.BufferGeometry(), flyBase = [];
  for (let i = 0; i < 26; i++) flyBase.push([W0 + rand() * (W1 - W0), 0.6 + rand() * 2, D0 + 1 + rand() * (D1 - D0 - 2), rand() * 6]);
  flyGeo.setAttribute("position", new THREE.Float32BufferAttribute(new Float32Array(flyBase.length * 3), 3));
  scene.add(new THREE.Points(flyGeo, new THREE.PointsMaterial({ color: C.glow, size: 1, sizeAttenuation: false })));

  // ---------------------------------------------------------------------------------------------- agents
  const agents = data.map((a, i) => {
    const g = new THREE.Group(); scene.add(g);
    const darker = new THREE.Color(a.color).multiplyScalar(0.7).getHex();
    const legs = [cube(g, C.dark, 0.24, 0.42, 0.24, -0.17, 0.21, 0), cube(g, C.dark, 0.24, 0.42, 0.24, 0.17, 0.21, 0)];
    cube(g, a.color, 0.72, 0.75, 0.46, 0, 0.8, 0);
    const arms = [cube(g, darker, 0.18, 0.56, 0.2, -0.46, 0.84, 0), cube(g, darker, 0.18, 0.56, 0.2, 0.46, 0.84, 0)];
    cube(g, C.cream, 0.62, 0.56, 0.56, 0, 1.46, 0);
    cube(g, C.dark, 0.1, 0.12, 0.03, -0.14, 1.5, 0.29, 0, false); cube(g, C.dark, 0.1, 0.12, 0.03, 0.14, 1.5, 0.29, 0, false);
    cube(g, C.stone, 0.06, 0.32, 0.06, 0, 1.9, 0, 0, false);
    cube(g, a.color, 0.15, 0.15, 0.15, 0, 2.1, 0, 0.9, false);
    const carry = cube(g, a.color, 0.34, 0.34, 0.34, 0, 1.05, 0.42, 0.8, false); carry.visible = false;
    const bubble = new THREE.Group(); bubble.position.set(0, 2.55, 0); bubble.visible = false; g.add(bubble);
    const dots = [-0.22, 0, 0.22].map(x => cube(bubble, C.cream, 0.13, 0.13, 0.13, x, 0, 0, 0.6, false));
    const hit = new THREE.Mesh(box, hitMat()); hit.scale.set(1.1, 2.4, 1.1); hit.position.y = 1.1; hit.userData = { kind: "agent", index: i }; g.add(hit); hits.push(hit);
    const home = homes.get(a.id) ?? 0;
    g.position.set(home + (rand() - 0.5), 0, HOUSE_Z + 2.4);
    return { ...a, g, legs, arms, carry, bubble, dots, home, path: [], state: "idle", timer: 1 + rand() * 4, cool: 3 + rand() * 4,
             speed: 2 + rand() * 0.6, phase: rand() * 6, with: null, activity: "Taking a break at home" };
  });
  const byId = Object.fromEntries(agents.map(a => [a.id, a]));
  const supported = a => a.status === "today";

  // ------------------------------------------------------------------------------------ behaviour
  const door = a => new THREE.Vector3(a.home, 0, HOUSE_Z + 2.3);
  const route = (from, to) => {
    const pts = [];
    if (Math.abs(from.z - ROAD_Z - 0.5) > 0.2) pts.push(new THREE.Vector3(from.x, 0, ROAD_Z + 0.5));
    pts.push(new THREE.Vector3(to.x, 0, ROAD_Z + 0.5), to.clone());
    return pts;
  };
  function next(a) {
    const r = rand(), at = a.g.position;
    const others = agents.filter(o => o !== a);
    if (a.state === "deliver") { a.state = "home"; a.path = route(at, door(a)); a.activity = "Heading home"; return; }
    if (a.state === "visit" || a.state === "home" || a.state === "chat" || a.state === "work" || a.state === "idle") {
      if (r < 0.55) {
        a.state = "deliver"; a.carry.visible = true;
        const side = a.home < 0 ? -1.6 : 1.6;
        a.path = route(at, new THREE.Vector3(TOWER.x + side, 0, TOWER.z + 3));
        a.activity = supported(a) ? "Carrying tokens to the Clepso tower" : "Bringing tokens Clepso can't read yet";
      } else if (r < 0.8) {
        const o = others[Math.floor(rand() * others.length)];
        a.state = "visit"; a.with = o; a.path = route(at, door(o).add(new THREE.Vector3(rand() < 0.5 ? -1 : 1, 0, 0.6)));
        a.activity = `Visiting ${o.name}`;
      } else {
        a.state = "work"; a.timer = 3 + rand() * 3; a.path = Math.abs(at.x - a.home) > 1.5 || Math.abs(at.z - (HOUSE_Z + 2.3)) > 0.5 ? route(at, door(a)) : [];
        a.activity = "Working in the workshop";
      }
    }
  }

  const flying = [], orbit = [];
  function drop(a) {
    a.carry.visible = false;
    const m = cube(scene, supported(a) ? a.color : C.grey, 0.32, 0.32, 0.32, 0, 0, 0, supported(a) ? 1 : 0.2, false);
    const from = a.g.position.clone().add(new THREE.Vector3(0, 1.1, 0));
    flying.push({ m, from, t: 0, ok: supported(a) });
  }

  function step(dt, t) {
    for (const a of agents) {
      a.cool -= dt;
      if (a.state === "chat") {
        a.timer -= dt;
        a.dots.forEach((d, k) => { d.position.y = Math.max(0, Math.sin(t * 6 - k * 0.8)) * 0.15; });
        if (a.timer <= 0) { a.bubble.visible = false; a.state = "idle"; a.timer = 0.3; }
        pose(a, t, false); continue;
      }
      if (a.path.length) {
        const target = a.path[0], pos = a.g.position, d = target.clone().sub(pos); d.y = 0;
        const len = d.length();
        if (len < 0.05) { a.path.shift(); if (!a.path.length) arrive(a); }
        else {
          pos.addScaledVector(d.normalize(), Math.min(len, a.speed * dt));
          a.g.rotation.y = Math.atan2(d.x, d.z);
        }
        pose(a, t, true);
      } else {
        a.timer -= dt;
        if (a.state === "work") { a.g.rotation.y = Math.PI; a.arms[1].rotation.x = Math.sin(t * 9) * 0.9; }
        pose(a, t, false);
        if (a.timer <= 0) next(a);
      }
    }
    // Two agents passing on the road stop to compare notes.
    for (let i = 0; i < agents.length; i++) for (let j = i + 1; j < agents.length; j++) {
      const a = agents[i], b = agents[j];
      if (a.state === "chat" || b.state === "chat" || a.cool > 0 || b.cool > 0) continue;
      if (a.g.position.distanceTo(b.g.position) > 1.25) continue;
      for (const [x, y] of [[a, b], [b, a]]) {
        x.saved = { path: x.path, state: x.state, activity: x.activity };
        x.state = "chat"; x.timer = 2.4; x.cool = 12; x.bubble.visible = true; x.with = y; x.activity = `Comparing notes with ${y.name}`;
        x.g.rotation.y = Math.atan2(y.g.position.x - x.g.position.x, y.g.position.z - x.g.position.z);
      }
    }
    for (const a of agents) if (a.state === "idle" && a.saved) { Object.assign(a, a.saved); a.saved = null; }
    // Tokens fly to the tower: readable ones join the glow, the rest fall back grey.
    for (let k = flying.length - 1; k >= 0; k--) {
      const f = flying[k]; f.t += dt / 0.9;
      const top = new THREE.Vector3(TOWER.x, 6.6, TOWER.z);
      if (f.ok) {
        const p = f.from.clone().lerp(top, f.t); p.y += Math.sin(f.t * Math.PI) * 2.2; f.m.position.copy(p);
        if (f.t >= 1) { flying.splice(k, 1); orbit.push({ m: f.m, a: rand() * Math.PI * 2 }); if (orbit.length > 18) scene.remove(orbit.shift().m); }
      } else {
        const p = f.from.clone().lerp(top, Math.min(f.t, 0.7)); p.y += Math.sin(Math.min(f.t, 0.7) * Math.PI) * 2.2 - Math.max(0, f.t - 0.7) * 9;
        f.m.position.copy(p);
        if (f.t >= 1.15) { flying.splice(k, 1); scene.remove(f.m); }
      }
    }
    orbit.forEach((o, k) => { o.a += dt * 0.9; o.m.position.set(TOWER.x + Math.cos(o.a + k) * 1.9, 6.6 + Math.sin(t * 2 + k) * 0.3, TOWER.z + Math.sin(o.a + k) * 1.9); });
    // The tower beats.
    const ph = (t % 1.3) / 1.3, beat = ph < 0.08 ? ph / 0.08 : ph < 0.2 ? 1 - (ph - 0.08) / 0.12 : ph > 0.28 && ph < 0.36 ? 0.45 * Math.sin((ph - 0.28) / 0.08 * Math.PI) : 0;
    core.material.emissiveIntensity = 0.7 + beat * 1.6; core.scale.setScalar(1.3 * (1 + beat * 0.1));
    beacon.intensity = 25 + beat * 55;
    const fp = flyGeo.attributes.position;
    flyBase.forEach(([x, y, z, s], i) => fp.setXYZ(i, x + Math.sin(t * 0.6 + s) * 1.2, y + Math.sin(t * 1.3 + s * 2) * 0.4, z + Math.cos(t * 0.5 + s) * 0.8));
    fp.needsUpdate = true;
    starMat.opacity = 0.65 + Math.sin(t * 0.7) * 0.15;
  }
  function arrive(a) {
    if (a.state === "deliver") { drop(a); a.timer = 0.6; a.g.rotation.y = Math.PI; return; }
    a.timer = a.state === "work" ? a.timer : 1.5 + rand() * 3;
    if (a.state === "visit") a.activity = `Visiting ${a.with.name}`;
    if (a.state === "home") { a.state = "idle"; a.activity = "Taking a break at home"; }
  }
  function pose(a, t, walking) {
    const s = walking ? Math.sin(t * 10 + a.phase) : 0;
    a.legs[0].rotation.x = s * 0.6; a.legs[1].rotation.x = -s * 0.6;
    if (a.state !== "work") { a.arms[0].rotation.x = -s * 0.5; a.arms[1].rotation.x = a.carry.visible ? -1.2 : s * 0.5; a.arms[0].rotation.x = a.carry.visible ? -1.2 : a.arms[0].rotation.x; }
    a.g.position.y = walking ? Math.abs(s) * 0.06 : 0;
  }

  // -------------------------------------------------------------------------------------- camera and size
  let pan = 0, panTarget = 0, viewW = 72, selected = null, hovered = null, pix = 3;
  const VIEW_H = 15;
  function resize() {
    const w = stage.clientWidth, h = stage.clientHeight;
    pix = w < 700 ? 2 : 3;
    renderer.setSize(Math.max(1, Math.round(w / pix)), Math.max(1, Math.round(h / pix)), false);
    const aspect = w / h, viewH = Math.max(VIEW_H, Math.min(20, (W1 - W0 + 2) / aspect));
    viewW = viewH * aspect;
    Object.assign(camera, { left: -viewW / 2, right: viewW / 2, top: viewH / 2, bottom: -viewH / 2 });
    camera.updateProjectionMatrix();
    panTarget = clampPan(panTarget); pan = clampPan(pan);
    draw();
  }
  const clampPan = p => { const room = Math.max(0, (W1 - W0) / 2 - viewW / 2 - 1); return Math.max(-room, Math.min(room, p)); };
  function place() {
    camera.position.set(pan, 21, 21);
    camera.lookAt(pan, 0.6, -1.6);
  }

  // --------------------------------------------------------------------------------------------- input
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  function pick(ev) {
    const r = canvas.getBoundingClientRect();
    ndc.set(((ev.clientX - r.left) / r.width) * 2 - 1, -((ev.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(ndc, camera);
    return ray.intersectObjects(hits, false)[0]?.object.userData || null;
  }
  let drag = null;
  stage.addEventListener("pointerdown", ev => { drag = { x: ev.clientX, pan: panTarget, moved: false }; });
  addEventListener("pointerup", ev => {
    if (drag && !drag.moved && stage.contains(ev.target)) {
      const hit = pick(ev);
      if (hit?.kind === "agent") select(hit.index);
      else if (hit) show(hit.kind);
      else select(null);
    }
    drag = null; stage.classList.remove("dragging");
  });
  stage.addEventListener("pointermove", ev => {
    if (drag) {
      const dx = ev.clientX - drag.x;
      if (Math.abs(dx) > 4) { drag.moved = true; stage.classList.add("dragging"); }
      panTarget = clampPan(drag.pan - dx * viewW / stage.clientWidth);
      if (reduce) { pan = panTarget; draw(); }
      return;
    }
    const hit = pick(ev);
    hovered = hit?.kind === "agent" ? agents[hit.index] : null;
    stage.style.cursor = hit ? "pointer" : "";
    if (reduce) draw();
  });
  stage.addEventListener("pointerleave", () => { hovered = null; if (reduce) draw(); });
  roster.forEach(b => b.addEventListener("click", () => {
    const i = agents.findIndex(a => a.id === b.dataset.agent);
    select(selected === agents[i] ? null : i);
  }));

  const STATUS = { today: "Clepso reads it today", planned: "On the roadmap", requested: "Requested, not yet planned" };
  function select(i) {
    selected = i == null ? null : agents[i];
    roster.forEach(b => b.setAttribute("aria-pressed", String(selected?.id === b.dataset.agent)));
    if (!selected) { show(null); return; }
    const vx = selected.g.position.x;
    if (Math.abs(vx - pan) > viewW / 2 - 4) panTarget = clampPan(vx);
    show("agent");
    if (reduce) { pan = panTarget; draw(); }
  }
  function show(kind) {
    if (!kind) { card.hidden = true; card.replaceChildren(); return; }
    const el = (tag, text, cls) => { const x = document.createElement(tag); x.textContent = text; if (cls) x.className = cls; return x; };
    card.hidden = false;
    if (kind === "agent") {
      const a = selected;
      card.replaceChildren(el("b", a.name), el("span", STATUS[a.status], "village-chip s-" + a.status), el("p", a.note), el("p", "Now: " + a.activity, "village-now"));
    } else if (kind === "tower") {
      card.replaceChildren(el("b", "The Clepso tower"), el("p", "Every agent's tokens come here. The ones Clepso can read join the glow and stay on your Mac; the rest fall back until Clepso learns to read them."));
    } else {
      card.replaceChildren(el("b", "An empty plot"), el("p", "Saved for the next agent. Tell us which one you use."));
    }
  }

  // ---------------------------------------------------------------------------------------------- loop
  function labels() {
    const who = hovered || selected;
    if (!who) { label.hidden = true; return; }
    const v = who.g.position.clone().add(new THREE.Vector3(0, 2.9, 0)).project(camera);
    label.hidden = false; label.textContent = who.name;
    label.style.left = ((v.x + 1) / 2 * 100).toFixed(2) + "%"; label.style.top = ((1 - v.y) / 2 * 100).toFixed(2) + "%";
  }
  function draw() { place(); renderer.render(scene, camera); labels(); if (selected && !card.hidden) { const now = card.querySelector(".village-now"); if (now) now.textContent = "Now: " + selected.activity; } }

  let visible = true, last = performance.now(), acc = 0, clock = 0;
  new IntersectionObserver(es => { visible = es[0].isIntersecting; if (visible && !reduce) requestAnimationFrame(loop); }).observe(stage);
  function loop(now) {
    if (!visible || document.hidden) return;
    const dt = Math.min(0.1, (now - last) / 1000); last = now; acc += dt;
    if (acc >= 1 / 30) {
      clock += acc; step(acc, clock); acc = 0;
      pan += (panTarget - pan) * 0.12;
      draw();
    }
    requestAnimationFrame(loop);
  }
  document.addEventListener("visibilitychange", () => { if (!document.hidden && visible && !reduce) { last = performance.now(); requestAnimationFrame(loop); } });
  new ResizeObserver(resize).observe(stage);
  resize();
  if (reduce) {                                                     // a still scene: agents at work around the village
    agents.forEach((a, k) => { a.g.position.x = a.home + (k % 2 ? 1.2 : -1.2); a.g.rotation.y = 0; });
    step(0, 0.1); draw();
  } else requestAnimationFrame(loop);
  root.classList.add("live");
}

function hitMat() { return new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, colorWrite: false }); }
function mulberry(a) { return () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
