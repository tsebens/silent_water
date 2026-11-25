# AI-authored code-CAD: what the field knows (November 2026)

Research for the code-CAD spike (#343): can an AI agent write the parametric CAD for the sub's kit parts and other
industrial assets, instead of Tristan modelling them in Onshape? Companion to
[`ai_code_cad_spike.md`](ai_code_cad_spike.md), which records what was built and what it taught us. Web research;
figures are quoted from the primary sources linked, and vendor claims are marked as such.

## The short version

- **Valid code is not the problem any more; correct geometry is.** Compile-and-retry loops drive crash rates to
  roughly zero in every 2026 benchmark, yet about half of the executable outputs still miss a stated requirement
  (58% on [CADEngBench](https://arxiv.org/html/2608.09296)). The consistent weak spots are spatial: wrong workplane,
  wrong extrusion direction, mirrored placements, off-by-one feature counts, and anything beyond sketch-and-extrude.
- **The biggest measured win is a hard, kernel-measured gate before the agent may say "done".** Forcing the agent to
  read volume, bounding box and feature counts before claiming completion cut silent failures from 14.1% to 3.2% and
  raised success from 64% to 78% ([Done Is Not Correct](https://arxiv.org/html/2611.10063v1)). Executable property
  tests agree with human judgement far better (AUC 0.93) than Chamfer distance or a VLM judge (both about 0.66)
  ([CADTestBench](https://arxiv.org/html/2605.07807)).
- **Render-and-look helps for qualitative checks only.** Multi-view renders judged by a vision model recover about
  half of the flagged problems, gain nothing after round two, and can make things worse when bolted onto plain
  generation ([CRAFT](https://arxiv.org/html/2611.00076v1)). Three fixed views missed a visible gap in a frame that
  passed every metric ([CADSmith](https://arxiv.org/html/2603.26512)). Never let the VLM override a measurement.
- **build123d or CadQuery, pinned, with the installed docs in context.** Both sit on the same OCCT kernel the agent
  can query. CadQuery has the academic corpus; build123d has the 2026 practitioner and tooling momentum, and the
  API churn to go with it. OpenSCAD has the largest public corpus but no fillet or chamfer operator and no B-rep to
  measure. Zoo's KCL has been rewritten twice and evaluates in the cloud.
- **Regenerate from parameters rather than edit.** About 64% of "successful" edits silently damaged unrelated
  features ([BenchCAD](https://arxiv.org/html/2605.10865v1)); agents under iteration pressure hard-code numbers and
  lose the parameters ([IterCAD](https://arxiv.org/html/2606.13368v2)).

## 1. Academic and benchmark work, 2024–2026

| Work | Generates | Headline result | Reported failure modes |
|---|---|---|---|
| [Text2CAD](https://arxiv.org/abs/2409.17106) (NeurIPS 2024) | DeepCAD-style sketch-extrude tokens | Beats two-stage baselines on detailed prompts | Boxes and cylinders dominate; in later benchmarks lowest invalidity but near-zero IoU: "runs but wrong shape" |
| [Query2CAD](https://arxiv.org/abs/2406.00144) (2024) | FreeCAD Python macros, no training | Error-retry plus caption-based self-refine | Nearly all the gain is in the first iteration |
| [CADCodeVerify](https://arxiv.org/html/2410.05340v2) (ICLR 2025) | CadQuery; VLM writes and answers validation questions about renders | Compile 96.0→96.5%, point-cloud distance 0.155→0.127; two rounds, no gain beyond | VLM answers "unclear" 19–27% of the time; metrics miss small gaps |
| [LLM4CAD](https://par.nsf.gov/servlets/purl/10661922) (2025) | CAD programs from GPT-4/4V | Syntax and IoU scored separately | GPT-4V did better text-only than text plus image |
| [CAD-GPT](https://arxiv.org/abs/2412.19663) (AAAI 2025) | Construction sequences with spatial tokens | State of the art on its own data | Motivation: MLLMs misplace sketch origins and extrusion directions |
| [CAD-Recode](https://arxiv.org/abs/2412.14042) (ICCV 2025) | CadQuery from point clouds; 1M synthetic programs | Large gains; output editable by off-the-shelf LLMs | Sketch-extrude only |
| [BlenderLLM](https://arxiv.org/html/2412.14203) / [BlenderGym](https://arxiv.org/html/2504.01786v1) (2024–25) | bpy scripts | Verifier-side scaling beat bigger generators | Open models fail to emit runnable bpy over 75% of the time on procedural tasks; human–VLM verifier agreement 0.66 |
| [CAD-Coder (MIT)](https://arxiv.org/abs/2505.14646) / [CAD-Coder (Beihang)](https://arxiv.org/abs/2505.19713) (2025) | Image or text → CadQuery, fine-tuned | 100% valid syntax; best solid similarity vs GPT-4.5 | Real-image generalisation only "early signs" |
| [CADmium](https://arxiv.org/html/2507.09792) (2025) | Minimal JSON sketch-extrude, Qwen2.5-Coder LoRA | Invalidity 3.3% at 14B | Worse watertightness, 15× more dangling edges, no fillets or chamfers |
| [EvoCAD](https://arxiv.org/html/2510.11631) (2025) | CadQuery, evolutionary loop with render descriptions | Topology correctness 87.2% vs 80.5% | IoU flat; "incorrect topologies can have better spatial metrics" |
| [CRAFT](https://arxiv.org/html/2611.00076v1) (Nov 2025) | OpenSCAD via JSON IR, six orthographic views → VLM fix | IoU 0.236 vs 0.189 direct; 13 exposed parameters vs 4 | VLM correction fired on 80%, fixed 50%; added to plain generation it made results worse |
| [Done Is Not Correct](https://arxiv.org/html/2611.10063v1) (Nov 2025) | build123d; 122 kernel-measured checks | "Measure then claim": silent failures 14.1→3.2%, success 64→78% | Planner–coder–checker pipeline cut silent failures but gave no success gain; the win was the claim contract |
| [CADSmith](https://arxiv.org/html/2603.26512) (Mar 2026) | CadQuery; planner, coder, validator, refiner; Opus judges renders plus kernel metrics | Chamfer 28.4→0.74, IoU 0.81→0.96; 88/100 converged on iteration one | A frame with gaps between arms passed both metrics and the judge |
| [GIFT](https://arxiv.org/html/2603.27448) (Mar 2026) | Image → CadQuery, kernel IoU filters training data | IoU 0.70→0.78 | Sampling mostly yields syntax errors, not semantic variety |
| [Zero-to-CAD](https://arxiv.org/abs/2604.24479) (Autodesk, Apr 2026) | 1M CadQuery programs from an execute-and-validate loop | Over 75% of good models needed at least one repair; 3.3 attempts average | Holes outside the part, oversize fillets, disconnected pieces |
| [BenchCAD](https://arxiv.org/html/2605.10865v1) (May 2026) | 17,900 standards-driven CadQuery programs | Frontier image→code: Gemini 3.1 Pro 0.397, Claude Opus 4.7 executes 94% but IoU 0.274 | About 64% of "successful" edits silently corrupt unrelated features; threads and chamfers dropped |
| [CADTestBench](https://arxiv.org/html/2605.07807) (May 2026) | Reference-free executable CadQuery tests | Tests agree with humans AUC 0.93 vs Chamfer 0.66, VLM judge 0.66 | Execution feedback gives 0% invalidity yet many outputs fail dimensional checks |
| [Text2CAD-Bench](https://arxiv.org/html/2605.18430v1) (May 2026) | 600 prompts, four difficulty levels | GPT-5.2 easy: IoU 0.59; hard: invalidity 68%, IoU 0.23 | Sweep, loft and shell fail; survivorship bias in metrics |
| [IterCAD](https://arxiv.org/html/2606.13368v2) (Jun 2026) | Drawing → CadQuery, RL, five turns with annotated views | Invalidity 6.5→0.3%, 2.4 turns average | Agent "favours geometric convergence over maintainability": hard-coded, non-parametric code |
| [CADEngBench](https://arxiv.org/html/2608.09296) (Aug 2026) | CadQuery plus STEP, FEA and physics | Of 2,400 programs 1,030 execute, 432 meet the brief | Parameters that "work" but give 3× wrong stress; assembly end to end 7.5–15.8% |

Also: [CADDesigner](https://arxiv.org/html/2508.01031) (build123d had the highest pass rate and the lowest IoU),
[Human-in-the-loop evaluation](https://arxiv.org/html/2509.07010), [CADGenBench](https://github.com/huggingface/cadgenbench)
(uses Betti numbers for topology), [CADIR](https://arxiv.org/pdf/2608.00891), a
[mechanical-engineering skills library](https://arxiv.org/html/2611.05758).

## 2. Which language models do best with

There is no controlled head-to-head benchmark of CadQuery against build123d, OpenSCAD and KCL. What exists:

- **CadQuery** is the de-facto academic target (CAD-Recode, both CAD-Coders, EvoCAD, CADSmith, GIFT, Zero-to-CAD,
  BenchCAD, CADTestBench, CADEngBench, IterCAD), with over a million public synthetic programs. Text2CAD-Bench found
  that switching from CadQuery to command sequences roughly tripled invalidity for several models. Known hazards:
  implicit stack state in long fluent chains (CADDesigner: 87.5% success vs 100% for an explicit-state wrapper),
  terse OCCT errors, and silent boolean drops: a union lost a cylinder, leaving 68% of the volume, while `isValid()`
  passed ([Forgent3D](https://www.forgent3d.com/en/blog/ai-cad-languages), a vendor).
- **build123d** is where 2026 practitioners and the CADGenBench leaderboard have moved. Forgent3D (which sells a
  build123d platform) reports every top-ten CADGenBench entry naming a tool uses it, and the
  [build123d-mcp](https://github.com/pzfreo/build123d-mcp) README claims validity 88→100% with its tools; both are
  self-reported. Counter-evidence: [Druckworks](https://druckworks.eu/guides/openscad-or-build123d-with-ai) lost
  runs with both Opus 5.5 and GPT-6 to build123d 0.13 API churn (`Shell.is_closed` gone, `&` raising on an empty
  intersection); one model averaged 0.4 errors per generation in OpenSCAD against 1.4–1.7 in build123d.
- **OpenSCAD** has the largest corpus and a stable syntax, so the fewest syntax errors, but it is mesh-only, has no
  fillet or chamfer operator, and "geometry rarely errors, so wrong parts still render". Will Patrick's
  [25-task evaluation](https://willpatrick.xyz/technology/2025/04/23/teaching-llms-how-to-solid-model.html) of 15
  models: reasoning models on top, five-operation tasks at 3–30% pass, Zoo's API below LLM→OpenSCAD. Recurrent
  failures: Z-up/Y-up confusion, lost solid/void state in nested CSG, hallucinated BOSL functions, no epsilon on
  coincident faces ([dev.to](https://dev.to/alanwest/why-llms-fail-at-openscad-code-generation-and-how-to-fix-it-2bel)).
- **KCL (Zoo)** was designed for LLMs but has little training data and has been reworked twice; models remember the
  old syntax. **FeatureScript** suits reusable features, not whole parts. **Fusion and SolidWorks APIs** return
  `False` or empty objects instead of errors. **bpy** is strong for scenes and organic forms, "not a precision CAD
  tool".

Net: data volume favours OpenSCAD > CadQuery > build123d >> KCL; measurability favours CadQuery and build123d; API
stability favours OpenSCAD and CadQuery over build123d 0.x. Everyone who measured says: pin the version and put the
installed library's docs or source in context.

## 3. Verification loops, ranked by evidence

1. **Kernel measurements plus a hard gate before "done".** Strongest and cheapest. The "measure then claim"
   contract is the single biggest gain anywhere; the same feedback without the contract gave almost no gain.
   CADSmith's watertight check plus volume, bbox, centre of mass and face counts took Chamfer from 28 to 0.74.
   Encode the spec as executable property tests rather than a comparison to a reference mesh.
2. **Compile and retry.** Nearly free, removes essentially all crashes, does nothing for wrong geometry. Cap at
   three; the gain is in rounds one and two.
3. **Multi-view render → VLM critique.** Helps with caveats: removing vision from CADSmith raised hard-tier Chamfer
   from 1.4 to 49.7, but CRAFT found it hurt plain generation, and [LLMForge](https://arxiv.org/html/2607.05573)
   saw VLM scores rise from 0.60 to 0.82 while the geometry stayed invalid. Use three to six views, cap at two or
   three rounds, and ask about qualitative things ("is there a hole here", "is the handle on the right side"), not
   dimensions.
4. **Generate several and pick.** At small budgets more candidates beat more critique (BlenderGym); the gap shrinks
   as the model improves (GIFT).
5. **Topology checks** (Euler characteristic, Betti numbers) catch missing or extra holes that distance metrics
   miss, cheaply, on a watertight mesh.

## 4. Practitioner workflows

- [El Cacharrista](https://www.elcacharrista.com/en/articles/vibe-coding-3d-design-openscad/): Claude Code plus an
  OpenSCAD monorepo where projects depend only on `components/` and `lib/`; layered CLAUDE.md; hooks that force all
  mesh work through repo tools (slice, render, deviation heat-map, collision check, outline and volume compare).
  Lesson: a few generic tools beat many specific ones, and Claude's default of writing ad-hoc trimesh scripts has to
  be suppressed.
- [Druckworks](https://druckworks.eu/guides/openscad-or-build123d-with-ai): library version drift was the top cause
  of lost runs; Opus caught a wrong-shaped hole only through an orientation check it had written itself.
- [Roshan George](https://wiki.roshangeorge.dev/w/Blog/2026-04-24/Modeling_Better_With_Claude): moved from OpenSCAD
  to build123d for chamfers; Claude kept trying to write raw STL; judged outputs by the model, never the code.
- [VibeCAD](https://github.com/rawwerks/VibeCAD): a Claude Code plugin marketplace with a build123d skill (bundling
  bd_warehouse threads and fasteners, and gggears), `render-glb` (so the agent can see), `model-compare` (IoU
  against a gold mesh) and `gltf-transform` (simplification). The closest thing to a game-asset scaffold found.
- MCP servers: build123d-mcp (execute, PNG/SVG preview, measure, find holes, a `validate()` export gate),
  [openscad-mcp-server](https://pypi.org/project/openscad-mcp-server/) (eight-angle renders, forces reading library
  source first), [cadquery-mcp](https://pypi.org/project/cadquery-mcp/) (SVG only). A vendor comparison of ten is
  at [buildcad.ai](https://buildcad.ai/guides/cad-mcp-servers).
- Hacker News threads ([SynapsCAD](https://news.ycombinator.com/item?id=47183039),
  [CADAM](https://news.ycombinator.com/item?id=45140921)) repeat the same report: models describe flaws in a render
  but cannot reliably correct them; a threaded nut took six iterations; evaluation outputs were "deficient in some
  way my eval didn't capture".
- Blender MCP for game props: good for low-poly placeholders and blockouts with a render-and-look loop, not hero
  assets; no systematic benchmark.

## 5. Commercial products

| Product | What it does | Code or direct geometry | Public API | Pricing, as stated |
|---|---|---|---|---|
| [Zoo](https://zoo.dev/research/zookeeper) Text-to-CAD, Zookeeper, KCL | Text-to-CAD generates and edits a B-rep; Zookeeper (Jan 2026) is an agent that writes and debugs KCL with mass, volume and snapshot checks | ML model → B-rep; Zookeeper → KCL | REST plus open-source [zoo-mcp](https://github.com/KittyCAD/zoo-mcp) | Usage-based; Design Studio Free, Plus $20, Pro $99. Independent tests ([Xometry](https://xometry.pro/en/articles/text-to-cad-tools-test/)): simple brackets fine, a 24-tooth gear inaccurate, a hole pattern shifted 5 mm |
| [Adam](https://techcrunch.com/2025/10/31/yc-alum-adam-raises-4-1m-to-turn-viral-text-to-3d-tool-into-ai-copilot/) / [CADAM](https://github.com/Adam-CAD/CADAM) | CADAM: open-source text → OpenSCAD in the browser, parameters exposed as sliders; Adam Copilot works inside Onshape and Fusion | OpenSCAD code | None found | Free, Pro $40, Max $200 |
| [Onshape](https://www.onshape.com/en/blog/ai-artificial-intelligence-cloud-native-cad-pdm-platform) | AI Advisor is a help chatbot; Labs has a FeatureScript MCP server and co-complete | FeatureScript features, early access | REST; community MCP servers | Advisor on all plans |
| [Autodesk Fusion](https://help.autodesk.com/cloudhelp/ENU/Fusion-MCP/files/FMCP-OVERVIEW.htm) | Drawing automation, auto-constrain, assistant with text-to-command; an official local MCP drives a live session; "Neural CAD" text → B-rep announced, not released | Command execution; Neural CAD direct | Fusion API plus MCP | $85/month |
| [Backflip](https://develop3d.com/cad/backflip-introduces-mesh-to-cad/) | Scan or mesh → feature tree in Fusion or SolidWorks | Direct, predicts feature ops | Not stated | $20 per 100 credits |
| [Leo AI](https://www.engineering.com/leo-ai-can-now-generate-full-cad-assemblies/) | Generates assemblies with a feature tree for SolidWorks, Onshape, CATIA | Not disclosed | None public | Enterprise |
| Spectral Labs SGS-1 | Image or mesh → STEP B-rep model; "parametric" claim disputed | Direct B-rep | Unclear | Not stated |
| Shapr3D | Generative render and a help chatbot only | None | None | n/a |
| Meshy, Tripo, Spline | Mesh generators; Tripo P2.0 adds quad output and budgets; Meshy's hard-surface accuracy lags | Direct mesh | Yes | Credits |

Only Zoo, Adam and Backflip have third-party hands-on tests, and all show the pattern the papers show: single-feature
parts work, multi-feature parts drift or fail. No vendor publishes a number on a public suite.

## 6. The toolchain: CAD code to a low-poly glTF

Measured in this container (Blender 4.5.3, Godot 4.7.2, Python 3.13) as well as read.

- **Install.** build123d 0.13.0 (September 2026, OCP 8.0.1) installs with `uv` on Python 3.13 first time; the
  virtualenv is about 870 MB, almost all the OCCT binding ([cadquery-ocp wheels](https://pypi.org/project/cadquery-ocp/#files)
  are 67 MB compressed, cp311–cp314 manylinux). CadQuery 2.8.0 (June 2026) still tells pip users to stay on
  Python 3.9–3.12. build123d 0.12 was the big breaking release, three days before 0.13.
- **Two authoring styles.** build123d's builder mode (`with BuildPart():` context managers) versus
  [algebra mode](https://build123d.readthedocs.io/en/stable/key_concepts_algebra.html) (stateless expressions:
  `Plane.XZ * Pos(X=-1) * Box(1, 2, 3) + Cylinder(0.2, 5)`). Algebra mode is the cleaner LLM target: short, pure,
  no hidden stack. CadQuery is fluent chaining with string selectors.
- **Tessellation.** OCCT's mesher takes a linear deflection (chord distance, model units) and an angular deflection
  (radians between segments). A 2 mm by 18 mm cylinder: default (0.001, 0.1) gives 500 triangles; (0.05, 0.5) gives
  100; (0.5, 1.0) gives 48. A 12-gon prism gives 44 at any tolerance, and faceting becomes a design choice. A
  chamfered 12-gon prism is 92 triangles; the same with a 0.3 mm fillet is 380 at coarse settings and 1,772 at the
  default. So: **prisms with an explicit side count, chamfers only, never fillets.** `Shape.tessellate()` reuses the
  cached triangulation; call `BRepTools.Clean_s(shape.wrapped)` before re-meshing coarser.
- **Native glTF export.** `export_gltf` writes labels as node names and `shape.color` as a material, but one
  primitive per B-rep face (a box with a hole is eight surfaces, eight draw calls in Godot) and, for colour-only
  parts, `metallicFactor` and `roughnessFactor` default to 1, so parts come in as dark metal. OCCT's writer can merge
  faces but build123d does not expose it ([RWGltf_CafWriter](https://occt3d.com/dev/doc/refman/html/class_r_w_gltf___caf_writer.html)).
  A Blender pass (merge by distance, limited dissolve, flat shade, triangulate) collapses the faces to one surface per
  mesh and fixes the materials; this is what the kit importer already does.
- **Hierarchy and pivots.** build123d `Compound(label=…, children=[…])` nests parts with relative locations, and
  [joints](https://build123d.readthedocs.io/en/stable/joints.html) (`RevoluteJoint` on the body, `RigidJoint` on the
  bat, `connect_to`) place a moving part with its own origin on the hinge. Verified end to end: the GLB carried
  `toggle_bat` with the hinge translation, and Godot imported it as a child node that rotates about the hinge.
  CadQuery does the equivalent with `Assembly.add(name=, color=, loc=)` but has no joint objects.
- **Headless rendering without a GPU.** Blender Workbench renders a 256 px frame in about 2 s on CPU with Mesa's
  surfaceless EGL (warnings but valid PNGs); Cycles at 8 samples 3 s; EEVEE 29 s. pyrender needs a custom OSMesa
  build; VTK 9.5 wheels do offscreen rendering and are what [CADSmith](https://arxiv.org/html/2603.26512v1) uses;
  build123d's `project_to_viewport` plus `ExportSVG` gives hidden-line drawings with no GPU at all. Workbench with
  flat lighting, material colour and cavity is the right tool for silhouette critique.
- **bpy as author.** [BlenderMCP](https://github.com/ahujasid/blender-mcp) is good for blockouts, but mesh
  booleans "carry the mess booleans always carry", there is no exact geometry, no STEP and no budget control.
  [sand3d](https://github.com/Sandflow-ai/sand3d) wraps bpy in a compact API with named parts and joints. Verdict:
  bpy is the post-processor and renderer, not the author.
- **OpenSCAD.** 2026.11-RC0 is the first release candidate since 2021; Manifold is the default backend (5–30×
  faster than CGAL). Exports STL, 3MF (colour only there), no glTF, no named parts, no hierarchy, no chamfer
  operator. Fine for single static props, wrong for pivoted assemblies.

## What this means for Silent Water

- **Library:** build123d, pinned, with the installed version's docs vendored. It gives a queryable kernel (volume,
  bbox, face and edge counts, `is_valid`) and chamfers; Blender stays a post-process. CadQuery is the fallback if
  0.x churn costs too many runs.
- **Loop:** a short structured brief (frame, bounding box, feature list with counts and positions, triangle budget,
  moving parts and hinges) → one feature at a time → compile-retry capped at three → **a hard gate of geometric
  assertions written against the brief, which the agent must pass before it may claim done** → four to six renders
  for qualitative review, capped at two rounds → export. Store the script, never the mesh; variants are parameter
  edits or re-prompts, not mesh edits.
- **Pitfalls to design around:** spatial errors dominate, so test workplane, direction and placement explicitly;
  assert volume to catch silent boolean drops; lint for a parameter block so iteration does not hard-code numbers;
  scope each part to a handful of operations and compose stations from verified parts; never let a render review
  override a measurement.
