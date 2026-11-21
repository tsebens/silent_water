# Lock the concept, then split the pipeline

Tristan's hypothesis holds up, with one important change. Locking 2D concept art first, in a Claude-mediated dialogue with an image model, is the right front end. But one "image-to-3D, then Blender cleanup" path should not serve every asset. The evidence points to two build routes behind a shared concept stage. **Organic and irregular forms go through hosted image-to-3D and then scripted headless Blender cleanup.** This covers creatures, including the ~30 m blind apex, plus unique seabed formations and a few odd props. **Brutalist modular architecture and the sub's interior props are built directly as parametric bpy scripts.** For these, the locked concept is a visual target, not a mesh source, because AI meshes are weak at the exact dimensions, snapping and repeated topology that kits need ([Wavect](https://wavect.io/blog/ai-3d-model-generators-game-development-2026/)). Either way, the concept stage has to end in a specific handoff. That handoff is a flat-lit, neutral-background **orthographic turnaround plus a written asset brief** (metres, triangle budget, snap grid, palette, emissive placement), not a pretty hero painting. Lighting painted into concepts gets baked into meshes as false surface relief ([Tripo](https://www.tripo3d.ai/blog/explore/using-concept-art-to-drive-ai-3d-outputs)). Money is not the constraint. Image generation costs cents per image, and 400 textured 3D generations cost roughly **$90–$300** at listed prices. The real risks are cross-asset style drift, unbenchmarked turnaround consistency, monthly model churn and licensing, Hunyuan3D's territorial exclusion above all. Everything fits Silent Water's GPU-less containers, because every generator is a hosted REST API and all cleanup runs in Blender 4.5 on CPU. The existing `3d_asset` role should evolve, not be replaced. Its three Blender proof-of-concept models become three 2D concept variations, and the role splits into an "art director" stage and a "builder" stage joined by labels.

## The concept-first approach works if the handoff is orthographic and measured

No one has published this exact pattern: Claude iterating concept art with a human through GPT Image or Gemini, then a second Claude instance building the asset in Blender. A 2026 survey looked for it and found nothing closer than viewport-screenshot feedback tools ([yage.ai](https://yage.ai/share/creative-ai-automation-survey-en-20260428.html)). Every part is documented, though. OpenAI's Responses API supports multi-turn image refinement by chaining `previous_response_id` ([OpenAI](https://developers.openai.com/api/docs/guides/tools-image-generation)). Meshy's official MCP describes its flow as "see concept images first, pick the one you like, and get it back as a textured 3D model" ([Meshy MCP](https://www.meshy.ai/mcp)). An ArtStation case study went from a character concept to a textured 3D mesh in under two hours: Nano Banana extracted the front, side and back views, and Hunyuan built the mesh ([ArtStation](https://okiyauchenna.artstation.com/projects/5W6EKP)). The pattern is feasible. What the evidence changes is the shape of the handoff.

The most rigorous public Claude Code asset pipeline, `blender-game-skills`, sets the handoff contract Silent Water should copy. The agent writes an `asset-brief.md` and crops the orthographic views. Every build-script constant is a measurement annotated with the view it came from, or is marked `# inferred`. Each phase is gated by **silhouette IoU against the reference (≥0.85 at blockout, ≥0.90 at forms)**. Mismatches have to be stated as measurements, such as "head 12% too tall", rather than "seems fine". Perspective art guides silhouette and detail only, never proportions ([blender-game-skills](https://github.com/majidmanzarpour/blender-game-skills)). That last rule matters most. A beautiful three-quarter painting from GPT Image is the right artifact for Tristan to approve. It is the wrong one to hand a builder.

Numeric gates are needed because Claude's visual self-critique is unreliable. 3DCodeBench found that frontier Claude models reach near-perfect *executability* with traceback retries: Opus 4.7 went from 0.910 single-shot to 1.000 with retries. But coding harnesses "mainly fix API errors" while shape quality barely moves. The dominant shape failure is "simplistic floating primitives" ([3DCodeBench](https://arxiv.org/html/2606.01057v1)). LL3M's VLM critic left watering-can handles disconnected after auto-refinement ([LL3M](https://arxiv.org/html/2508.08228v1)). In a Blender MCP donut test, Claude mistook the reference for its own render, and quality fell apart as context filled ([MindStudio](https://www.mindstudio.ai/blog/claude-blender-mcp-60-percent-tokens-donut-test-results)). The two-instance split Tristan proposed is therefore a strength. An art-director session holds the taste dialogue. A fresh builder session works from files, with short context, reproducible scripts and measured gates.

The live Blender MCP route should be dropped as the production path. The community MCP for Blender needs a running GUI Blender with a socket add-on. The official Blender Lab server's background `_for_cli` tools need Blender 5.1+, and the environment pins 4.5 LTS ([StraySpark comparison](https://www.strayspark.studio/blog/official-blender-mcp-server-comparison-2026)). Practitioners who tried both settle on "explore live, then codify into a headless build script". Headless runs give parallel agents, factory-reset reproducibility, enforced budgets and git diffs ([sumguy.com](https://sumguy.com/blender-mcp-vs-headless-bpy/)). That is what the graphic-designer role already does.

## GPT Image and Nano Banana for concepts, a bake-off for 3D

### Concept stage

Two image models cover the concept stage. **OpenAI GPT Image 2.5/2.6 Sunburst** leads both major leaderboards for generation and single-image editing. It supports transparent backgrounds, markup-guided edits and stateful multi-turn chains. Its tokens cost $8/M input and $30/M output ([OpenAI pricing](https://developers.openai.com/docs/pricing); [Digital Applied](https://www.digitalapplied.com/blog/gpt-image-2-6-vs-gemini-flux-seedream)). Use it for hero concepts and precise refinement edits. Set `complexity` to low or medium for view edits, because OpenAI warns that high adds "unwanted changes" ([OpenAI guide](https://developers.openai.com/api/docs/guides/image-generation)). **Google Nano Banana 2.1** costs **$0.0336 per 1K image** and takes up to 14 reference images, with consistency across 10 objects ([Google AI Studio](https://aistudio.google.com/docs/pricing); [Zeniteq](https://www.zeniteq.com/5-new-ai-image-models-to-know-in-november-2026-pufojn)). It is the workhorse for bulk exploration and for passing style anchors on every call. Nano Banana Pro (`gemini-3-pro-image`, $0.134) drives ComfyUI's official turnaround-sheet workflow ([Comfy hub](https://comfy.org/hub/workflows/character-turnaround-sheet-generator-ad315e41d8c2/)). Seedream 5.0 Pro ($0.045, 10 references, alpha layers) and FLUX 3 (10 references) are cheaper alternates. Midjourney has no API and is out.

There are two flagged uncertainties. OpenAI publishes no flat per-image price for 2.x models, and sources conflict on whether 2.6 is in the Batch tier. Leaderboards also measure general preference, not turnaround consistency or fitness for image-to-3D. No benchmark exists for either.

### Turnarounds and style

Turnarounds should be **reference-conditioned edits from one approved front view**: generate the front, then derive left, back and right with the front as reference #1. Dedicated multi-view diffusion models (MV-Adapter, Zero123++) are an older approach. They need a GPU, work at 768 px, and produce blurry or "not strictly 3D consistent" views ([GeoMVD](https://arxiv.org/pdf/2511.12204); [MVEdit](https://arxiv.org/pdf/2403.12032)). Vendor input rules converge. Use a single centered subject on a plain or transparent background, flat even light, at least 1024 px (2048 recommended), and no text. For multi-view input, keep scale and framing identical at 90° steps. Meshy, Tripo and Hunyuan all state these requirements ([Meshy](https://docs.meshy.ai/en/webapp/image-to-3d); [Tripo node](https://docs.comfy.org/built-in-nodes/TripoMultiviewToModelNode); [Hunyuan3D-2mv](https://huggingface.co/tencent/Hunyuan3D-2mv)). Turn off Meshy's Image Enhancement, which redraws the input.

Style consistency across assets is the most-cited unsolved problem in AI asset production, as Tripo's own CEO says ([80.lv](https://80.lv/articles/tripo-ceo-on-using-ai-to-augment-creators-not-replace-them)). Start with a committed `style_bible/` folder:

- a canonical prompt block
- 6–10 approved anchor images per category
- a negative list

Pass 2–4 same-category anchors on every call. Once 15–30 concepts are approved, consider Recraft V4 Styles (a reusable `style_id` from 1–10 images) or a FLUX LoRA on fal at about **$2–6.40 per 1,000 training steps**. The LoRA suits bulk props and rocks, where FLUX's weaker editing matters less ([Recraft API](https://www.recraft.ai/docs/api-reference/api); [fal fine-tuning](https://fal.ai/learn/devs/how-to-fine-tune-flux-with-the-api)).

### 3D stage

No trustworthy independent ranking exists. 3D Arena's live table couldn't be read, and other leaderboards are editorial or vendor-run ([Pixazo](https://www.pixazo.ai/leaderboard/ai-3d-model-generation)). The pick should come from a small in-house bake-off among four candidates:

| Service | Why it is in the bake-off | Main limitation | Approx. cost per textured generation |
|---|---|---|---|
| **Tripo H3.1** | Native `smart_low_poly` (500–20k faces); only documented non-humanoid auto-rig, including `aquatic` and `serpentine` types | P2 lacks smart low-poly; free-tier licence terms conflict | ~$0.40 incl. low-poly ([Tripo](https://developers.tripo3d.com/en/pricing), $0.01/credit unverified) |
| **Hyper3D Rodin Gen-2/2.5** | 1–5 input images; quad presets down to 4k faces; pitched for hero fidelity | Direct API needs the $120/month Business plan | ~$0.75 direct, $0.40 via fal ([Rodin spec](https://docs.hyper3d.ai/en/api-specification/rodin-gen2)) |
| **Meshy 7.1** | Mature API, multi-image input, remesh, UV and rig endpoints; failed tasks refunded | Rigging is humanoid-only; `lowpoly` model retired Oct 30, 2026 | ~$0.60 on the $20 Pro plan ([Meshy](https://docs.meshy.ai/en/api/pricing); [renderahouse](https://www.renderahouse.com/blog/meshy-pricing)) |
| **TRELLIS.2 via fal** | MIT licence, very cheap, PBR output | ~1M-face output by default; opacity stored but exported OPAQUE | ~$0.02–0.30, unverified ([TRELLIS.2](https://github.com/microsoft/TRELLIS.2)) |

Hunyuan3D 3.1 on fal ($0.225–0.375) has a high reported quality ceiling and sealed manifold meshes, but the source is a vendor blog ([3D AI Studio](https://www.3daistudio.com/blog/pixal3d-vs-trellis-2-vs-hunyuan-3d-comparison)). It is excluded by default for licensing reasons, covered below. Use **fal.ai** as the single aggregator key for the 3D endpoints and the secondary image models. Call OpenAI and Google directly for their flagship image models.

## Each asset class takes a different route

Under Silent Water's art direction, the key question for each class is "does it need exact dimensions and repetition, or irregular organic form?" Feel over detail, strong silhouettes and low poly count all favour scripted geometry for hard-surface work. Volumetric fog also makes silhouette and value matter more than surface texture. That pushes every class toward **flat colours or vertex colours rather than texture maps**, which also sidesteps de-lighting.

| Asset class | Build route | Why | Indicative budget (judgment) |
|---|---|---|---|
| Apex monster (~30 m, blind, coelacanth-like) | Concept → side/top/front orthos → multi-view image-to-3D (Tripo or Rodin) for the body → cleanup → fins rebuilt or generated separately → shader swim plus optional scripted bone chain | Organic mass suits AI; thin fins and gameplay motion do not | 10–20k tris |
| Smaller creatures (fish, eels) | Same as the apex, simpler; procedural vertex-shader swim, no rig | Godot's ABZU-style fish technique needs no skeleton | 2–8k tris |
| Brutalist station kit | Concept for massing and mood → **parametric bmesh script** on a 2/4 m grid with named sockets; neon strips as separate emissive geometry | Kits need snapping and repeated topology, where AI meshes fail | Per module, a few hundred to ~2k |
| Network equipment (buoys, junctions, sensor arrays) | Parametric bpy | Angular and slab-like by direction; exact interaction points | 200–3k |
| Sub interior props | Parametric bpy, matching the sub's matte modern look | Exact fit to the interior, which is a still scene; interaction points | 200–3k |
| Seabed rocks and terrain | Scripted noise displacement and decimation on icospheres or grids; AI (TRELLIS.2 or a Tripo low-poly) only for unique formations such as vents or arches | Few parameters, which LLMs handle well; the contrast rule needs soft organic shapes | 200–2k per piece |
| Irregular one-off props | Image-to-3D, then planar decimation | Occasional organic shapes not worth hand-scripting | 200–800 |

### Apex monster

The apex is the hardest asset in the project. Long thin parts such as fins are the highest-risk geometry for image-to-3D. TRELLIS.2's opacity handling also works against membrane fins ([TRELLIS.2](https://github.com/microsoft/TRELLIS.2)). The recommended handling:

- **Body:** generate from orthographic views with the fins extended and the body straight, the aquatic equivalent of an A-pose. The elongated body suits side/top/front views better than a strict four-view rig, and Hunyuan-style top views help here.
- **Fins:** build them as separate flat geometry.
- **Eyes:** none. "Blind" is a gameplay fact and should be a silhouette fact too. Say so in the brief, or the image model will add them.
- **Motion:** Godot's official fish technique puts all motion in the vertex shader. It drives sway, a travelling wave and twist from a 0–1 `body` parameter along the spine ([Godot docs](https://docs.godotengine.org/en/4.4/tutorials/performance/vertex_animation/animating_thousands_of_fish.html)). The cleanup script can bake that parameter into UV2 or vertex alpha. For a head that tracks the sub, add a scripted bone chain driven by `SkeletonModifier3D`.
- **Rigging:** Tripo's `aquatic` rig (25 credits) is worth one test, but no independent evaluation of it exists ([Tripo rig docs](https://developers.tripo3d.com/en/docs/animations-rig.md)). Meshy's rigging API is humanoid-only and returns 400 on non-humanoid input ([Meshy Rigging](https://docs.meshy.ai/en/api/rigging)).

### Architecture and neon

Brutalist architecture plays to Claude's strengths. Hard-surface and architectural scenes are where LLM-driven Blender works best, while Geometry Nodes trees "beyond a few nodes" get wrong connections ([MindStudio](https://www.mindstudio.ai/blog/claude-blender-mcp-real-world-performance)). Slabs, cantilevered tiers, ribbed soffits, splayed struts and ribbon-window slots should come from plain bmesh code that reads a kit spec (a Godot Resource or JSON). Keep emissive neon out of every input to image-to-3D. Generate concepts for 3D with "emissives off, flat-coloured", and add emission as a separate Godot material slot, so the glow is not baked into albedo. This is an untested inference, but cheap to respect.

## Cleanup and import run headless on four CPU cores

The cleanup recipe for AI meshes is triangle decimation, not quad retopology. Raw Meshy and Tripo output is "dense triangle soup" with non-manifold edges and flipped normals ([Seeles](https://www.seeles.ai/resources/blogs/ai-3d-model-cleanup-after-meshy-tripo-hunyuan)). Quad remeshers such as QRemeshify are GUI-only and Windows-first, and one user reported 30–60 minutes on Suzanne ([QRemeshify](https://github.com/ksami/QRemeshify)). Flat-shaded static props gain nothing from quads anyway.

The scripted pass runs in this order:

1. bmesh repair: merge by distance, drop loose and degenerate geometry, recalculate normals, drop floating shells.
2. Optional voxel remesh to weld the soup.
3. Decimate (Collapse) to the triangle budget, then Decimate (Planar) at 5–15° to merge facets.
4. Flat shading.
5. Sample the AI texture into a k-means palette of 8–16 vertex colours with luminance normalized per cluster. This removes painted-in lighting by construction.
6. Normalize scale and pivot from the brief's target dimension, with -Y forward and +Z up.
7. Add `-colonly` box or convex helpers for collision.
8. Export the GLB.

pymeshlab's quadric collapse, which Roblox cube3d and TripoSG use in production, and gltfpack (`-si`) are CPU fallbacks ([cube3d](https://huggingface.co/spaces/Roblox/cube3d-interactive/raw/0964e01c893b42a22a4caa34183d87d7f47342a5/cube/cube3d/mesh_utils/postprocessing.py); [gltfpack](https://raw.githubusercontent.com/zeux/meshoptimizer/master/gltf/README.md)). Several of these bpy calls come from training knowledge, not 2025–2026 sources: the decimate modifier types, voxel remesh, bake to vertex colours and the glTF vertex-colour option name. Each needs a one-time smoke test on 4.5.3.

Gates run in script, not by eye:

- a triangle-budget ratchet, where raising a budget requires an explicit override in the same commit
- a stdlib reader that pulls the triangle count from the GLB's JSON chunk
- a bmesh island and non-manifold count
- a check that the bounding box is within 1% of the brief
- silhouette IoU against the locked orthographic views
- a GLB re-import

These follow the sumguy and blender-game-skills practices, which built 17 GLBs from 8 parallel subagents with sub-second headless builds ([sumguy.com](https://sumguy.com/blender-mcp-vs-headless-bpy/)). For review renders, use **Workbench** (about 2.6 s per image once Mesa EGL is installed) for silhouette sheets. Use Cycles CPU, already verified in this container at about 30 s for 1280×960 with denoising, for emissive checks. Use Godot Forward+ under xvfb and lavapipe, also verified, for the in-engine shot with fog under white and red light. Label every contact sheet "REFERENCE" and "RENDER vN" so no model confuses the two.

On the Godot side, one shared `EditorScenePostImport` script, assigned via `import_script/path`, should solve the verified vertex-colour gotcha once for every asset. It sets `vertex_color_use_as_albedo` and enables backface culling, which Blender exports as disabled by default ([Godot formats](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/available_formats.html)). It should also assign collision layers. Gameplay nodes go in an inherited `.tscn`, so re-imports don't wipe them. Godot's automatic meshoptimizer LODs are on by default. Disable them per mesh for sub-1k props and skinned creatures, where the docs warn of issues ([Godot LOD](https://docs.godotengine.org/en/stable/tutorials/3d/mesh_lod.html)). Issue #92404, where Blender vertex colours look different in Godot (likely an sRGB problem), is unresolved for 4.7 and needs checking ([godot#92404](https://github.com/godotengine/godot/issues/92404)).

## A thin review app, wired into the label pipeline

No off-the-shelf tool combines variant review, prompt lineage and approval write-back to GitHub. The studio tools have the right vocabulary but are too heavy for one reviewer. Kitsu, for example, has "waiting for approval", playlists and GLB review with HDR lighting ([Kitsu](https://kitsu.cg-wire.com/review/)). The "asset development platform" should therefore be a **review surface, not a generation engine**. Generation stays in agent sessions, where API keys live as environment network secrets and every call lands in a provenance file. The app reads per-asset `asset.yaml` manifests from the repo. In priority order it shows:

1. A variant grid with A/B compare, plus approve, reject and refine buttons and a free-text note. The note becomes the next prompt turn verbatim.
2. Version lineage for every image: model ID, prompt, response ID or seed, and parent.
3. A `<model-viewer>` turntable of the GLB next to the locked orthographic views, with wireframe, triangle count, a neutral HDR and a dark "in-water" HDR ([modelviewer.dev](https://modelviewer.dev/)).
4. Pin annotations stored as comments.

Each decision writes back to GitHub as an issue comment and a label flip. The existing label-driven dispatcher and the hourly `3d_asset` task already consume labels, so the app never needs to talk to agents directly. It can be a static claude.ai Artifact or a GitHub Pages site authenticated with a fine-grained PAT. **Build it only after two or three assets have gone through plain GitHub issues**, which is the cheapest MVP the notes identify.

Interactive dialogue still has a place. For hero assets such as the apex, a live head-developer-style session in which Claude generates, shows and refines images with Tristan in real time will converge faster than an hourly async loop. Chaining needs `store: true`, and response IDs may expire. Save the PNGs and IDs in `asset.yaml`, and keep every model call behind a single adapter function, as CLAUDE.md requires for the network peer. gpt-image-1 shut down on Oct 23, 2026 ([OpenAI](https://developers.openai.com/api/docs/guides/tools-image-generation)), Meshy 7 requests error after Dec 31, and Meshy's lowpoly model has already retired.

### Integration with the current `3d_asset` workflow

The current workflow changes in four ways:

- **Step 4:** the three low-poly Blender proof-of-concept models become three 2D concept variations. They are cheaper, faster and avoid CPU render time, and are still committed to `concepts/<asset>/` with SHA permalinks.
- **New labels:** `asset:concept-review` → `asset:concept-locked` → `asset:model-review`.
- **Locking a concept:** produces the handoff bundle: orthographic views, `asset-brief.md` and `asset.yaml`.
- **The builder session:** picks up `asset:concept-locked`, chooses the route by asset class, and delivers to `assets/models/<asset>/` as today (script, `.glb`, `.tscn`), plus the raw generator GLB and the manifest.

Track binaries in Git LFS and purge rejected variants, because GitHub's free LFS quota is small.

## Costs stay small, and legal exposure clusters in three places

Costs are indie-trivial. A 20-iteration concept at high quality comes to under $5. At Nano Banana's $0.034, even 3,000 exploration images cost about $100. For 3D, 400 textured generations run about $160 on Tripo, about $240 on Meshy plus the subscription, $150 on Hunyuan via fal, and under $20 on TRELLIS. A mixed strategy stays under about $250 ([Tripo](https://developers.tripo3d.com/en/pricing); [fal Hunyuan](https://fal.ai/hunyuan-3d)). Routing architecture and sub props through scripts cuts image-to-3D volume further. The most likely large line item is Claude tokens, not generator credits. The donut test used about 60% of a 5x Max session's tokens in two hours of live MCP. That is another argument for short, script-based builder sessions. Rate limits and concurrency are unpublished for every vendor.

### Licensing and law

- **Copyright:** the US Copyright Office holds that purely prompt-generated material isn't copyrightable, but human selection and modification can be protected ([copyright.gov](https://copyright.gov/newsnet/2025/1060.html)). The provenance manifest and the Blender build scripts are the evidence of human authorship, so keep them.
- **Steam disclosure:** Steam's January 2026 rewrite requires disclosure of AI-generated content that players consume, in game or in store art, while efficiency tools are exempt ([VGC](https://www.videogameschronicle.com/news/valve-has-significantly-rewritten-steams-rules-for-how-developers-much-disclose-ai-use)). Expect to tick the box for creature meshes. Concepts used only as reference arguably fall outside the rule, but that reading is unconfirmed against Steamworks text.
- **Hunyuan3D:** Hunyuan3D 2.1's licence territory **excludes the EU, UK and South Korea** and bars use of outputs outside that territory ([LICENSE](https://huggingface.co/tencent/Hunyuan3D-2.1/blob/main/LICENSE)). A Steam game sells there, so avoid Hunyuan unless a lawyer clears the hosted 3.x terms, which are unverified.
- **Vendor plans:** use paid plans only. Meshy's free tier is CC BY 4.0, and paid tiers get a private commercial licence ([Meshy pricing](https://docs.meshy.ai/en/webapp/pricing)). Tripo's own pages conflict on free-tier ownership ([Tripo help](https://www.tripo3d.ai/help/privacy-policy/can-i-use-models-commercially)). TRELLIS.2 is MIT.
- **Image providers:** OpenAI's and Google's output terms were not retrieved and need checking before shipping.
- **Market signal:** itch.io's "No AI" tag shows that part of the audience avoids generative AI ([itch.io](https://itch.io/game-assets/tag-godot/tag-no-ai)).
- **Reference images (inference):** the architecture references include copyrighted film and artist concept art (*Underwater*, Patrik Rosander). Keep those as human-read references and out of image-model reference slots, so the style bible's anchors are the project's own approved outputs.

### Open risks

The open risks, roughly in order of impact:

1. Style drift across dozens of assets.
2. Unmeasured turnaround consistency for every image model.
3. Undocumented low-poly mode quality on stylized hard-surface.
4. Untested de-lighting by palette quantization.
5. Apex fins and Tripo's unvalidated aquatic rig.
6. Model churn.
7. No real-world hours-per-asset figure from any shipped indie project ([pipelines survey, Tripo checklist](https://www.tripo3d.ai/blog/explore/game-ready-checklist-for-ai-generated-assets)).

Two infrastructure gaps are concrete:

- **Workbench and EEVEE need `libegl1 libegl-mesa0 libgl1-mesa-dri`.** These are not yet in the environment setup script, so this is discovered work for the board.
- **Poly Pizza blocks cloud IPs with Cloudflare,** so the community Blender MCP's asset library is not reachable from the containers ([blender-mcp](https://github.com/ahujasid/blender-mcp)).

## Recommended pipeline and first experiments

| Stage | Owner | Tools | Handoff artifact |
|---|---|---|---|
| 0. Request | Dev agent or Tristan | GitHub issue, `3d_asset` label | Issue with scale, location, gameplay constraints |
| 1. Concept exploration | Art-director session (interactive for hero assets, hourly otherwise) | Nano Banana 2.1 (bulk, style anchors), GPT Image 2.6 Sunburst (hero, edits) | 3 variations in `concepts/<asset>/`, SHA-linked; `asset:concept-review` |
| 2. Lock | Tristan | Issue comment now; review app later | Chosen variation recorded; `asset:concept-locked` |
| 3. Turnaround and brief | Art-director session | Per-view low-complexity edits from the locked front (Nano Banana Pro or GPT Image), transparent background, 2048 px | Orthographic views, `asset-brief.md` (m, tris, grid, palette, emissives), `asset.yaml` |
| 4a. Organic build | Builder session | Bake-off winner (Tripo H3.1 / Rodin / Meshy 7.1; TRELLIS.2 for rocks) via REST or fal | Raw GLB plus task ID in the manifest |
| 4b. Hard-surface build | Builder session | Parametric bmesh script on Blender 4.5 | Build script as source of truth |
| 5. Cleanup and gates | Builder session | Headless Blender: repair, remesh, decimate, palette, scale, collision helpers; gate scripts | Clean GLB, JSON gate report, Workbench contact sheet |
| 6. Engine check | Builder session | Godot 4.7 import with shared post-import script; xvfb and lavapipe fog render, white and red light | `.glb`, `.import`, `.tscn` in `assets/models/<asset>/`; in-engine shots |
| 7. Approve | Tristan, then review agent | Issue now; app turntable later | `asset:model-review` → Done |

The first experiments to run, in order:

1. **Fix the environment.** Add the Mesa EGL packages to the setup script. Smoke-test every unverified bpy call on 4.5.3: decimate modes, voxel remesh, bake to vertex colours, glTF vertex-colour parameter name. Write the shared Godot post-import script and check for the #92404 colour shift.
2. **Build the style bible v0.** Run a concept loop on three test assets: the apex, one brutalist module, one sub prop. Compare GPT Image 2.6 Sunburst with Nano Banana 2.1, and per-view turnaround edits with a single 4-up sheet. Score cross-view consistency by silhouette IoU and height match.
3. **Run the image-to-3D bake-off.** Send the apex body, a seabed formation and an irregular prop through Tripo H3.1 (smart low-poly), Rodin Gen-2, Meshy 7.1 multi-image and TRELLIS.2, for under about $20. Score post-cleanup IoU, defect counts and wall time.
4. **Run the cleanup chain end to end on the winners,** through to Godot with fog, timing each stage on four cores.
5. **Do a brutalist kit spike.** Script 4–6 modules on a 4 m grid with neon channels, assemble a station vignette, and run one image-to-3D attempt on the same concept to confirm the routing split.
6. **Test apex motion.** Compare the baked spine parameter with shader swim against Tripo's `aquatic` rig.
7. **Build the review app MVP,** only after steps 2–4 have run through plain issues.

## Conclusion

The research reframes what "AI-assisted" means for Silent Water. AI is not the modeler. It is the **concept generator and the organic-mesh sculptor**, and Claude's real job is orchestration and measurement. Claude turns Tristan's taste into orthographic, dimensioned contracts, then holds every generated or scripted mesh to those contracts with numbers rather than impressions. The low-poly, fog-heavy, silhouette-first art direction is unusually forgiving of AI's weaknesses. Faceted decimation hides messy topology, and palette vertex colours erase baked lighting. Brutalism's rigid geometry is exactly what scripted bpy handles best. So the project's style choices make this pipeline more viable than it would be for a realistic game.

The decisive unknowns are empirical and cheap to settle: turnaround consistency, which 3D vendor survives cleanup best, and whether palette de-lighting looks right under fog. A first round of experiments costing well under $50 in API spend should answer them. The two-session split, labels and handoff bundle can be built before any vendor is chosen, because each model call sits behind an adapter that will need swapping within months regardless.
