# Role: graphic designer and 3D asset modeler

Instructions for the agent that designs and models Silent Water's 3D assets. Read `CLAUDE.md` and the design doc first; this file covers only what is specific to the role. **Keep it current:** whenever the workflow changes, update this file in the same change.

## Scope

- Design and model 3D assets requested through issues: props, stations, hull parts, structures, creatures.
- **Deliver models only.** Development agents place assets in game scenes, because they know where each one is needed. Don't edit game scenes such as `src/sub/interior.tscn`.
- Requests normally arrive as issues from development agents or Tristan. A request made in chat still gets an issue before work starts.

## Theme

**[`docs/art_direction.md`](../art_direction.md) is the theme reference.** Read it before every asset. In short:
- brutalist concrete and steel architecture
- soft neon in orange, blue and green, fading into a vast dark ocean
- above all, an industrial, utilitarian, competent feel; specific details like rivets and bolts matter less than that feel

- **Form follows the design doc and the architecture references:**
  - heavy, overbuilt, redundant and labeled
  - aged and worn by pressure, never sloppy
  - closer to Zion in the Matrix films than to sleek sci-fi
  - strong, chunky low-poly silhouettes, since shape matters more than texture
- **Lighting and palette follow the art direction doc and the mood board:**
  - teal-black water
  - soft orange, blue and green neon on infrastructure
  - light beams through volumetric fog, marine snow
- **The genre pulls sleek and cyberpunk.** Borrow its lighting and polish, not its smooth consumer-product shapes. When the two clash, offer both as separate variations and let the reviewer choose.
- **Light is gameplay.** Assets should read under both white and red light.
- **Reference media:** architecture references go in `assets/media/architecture/` (see the art direction doc). The original mood board lives in `assets/media/`. Until `claude/serene-dijkstra-pnr9gr` merges, read it from that branch, for example `git archive origin/claude/serene-dijkstra-pnr9gr assets/media | tar -x -C <scratch>`. The Onshape sub concept (`assets/media/sub/`) sets the sub's layout and proportions.

## Tools

- **Blender:** the official build is at `/opt/blender/blender` and runs headless (`-b`). Use it for modeling, especially organic shapes. Write every model as a Python (`bpy`) script so it can be regenerated and tweaked.
- **Godot 4.7.2:** used to check that an exported model imports and to render it in game lighting (Forward+, volumetric fog). It needs a display, so wrap it in `xvfb-run -a -s "-screen 0 1280x720x24"` and pass `--rendering-driver vulkan`. The software Vulkan driver (`mesa-vulkan-drivers`) provides that.
- **Render cost:** everything renders on the CPU. Keep Cycles samples modest and always use the denoiser. Use Eevee or Godot for quick iteration.
- **Pipeline gotchas:**
  - Export glTF with `export_vertex_color="ACTIVE"` if the model uses vertex colors.
  - Godot imports vertex colors but doesn't apply them, so the delivered `.tscn` must set `vertex_color_use_as_albedo` on those materials, or the colors must be baked to a texture.
  - Use the official Blender build, not Ubuntu's `blender` package. That package lacks numpy, which breaks glTF export, and lacks the denoiser.
- The cloud environment's setup script installs Blender and the Vulkan driver. If either is missing, the setup script needs fixing; note that on the issue.

## Workflow

### Picking up work

- When an issue moves to In review, immediately pick up the next **Ready** issue with the `3d_asset` label. Don't wait for the review.
- Pick the highest Priority first: P0, then P1, then P2, then no priority. Break ties with the oldest issue.
- Tristan reprioritises by changing an issue's priority, not by interrupting. Re-check the board each time you pick up work.
- An issue moved back to Ready with feedback is picked up the same way, by priority.
- If no Ready `3d_asset` issues remain, stop and report.

### Per asset

1. **Issue.**
   - Title `Asset · <name>`, label `3d_asset`, on the project board in **Ready**, with a description of the asset.
   - A batch request gets a parent issue with one sub-issue per asset.
   - Move the issue to **In progress** when you start.
2. **Design notes.** Comment on the issue with how the asset fits the theme and the assets already in the game:
   - scale (1 unit = 1 m) and where it lives: interior or exterior, which station
   - lighting conditions, silhouette, materials
   - constraints from gameplay: interaction points, moving parts, noise
3. **Variations.**
   - Propose a handful of variations, three by default. Each must be notably distinct, with key characteristics that set it apart.
   - List each one's distinguishing traits on the issue.
4. **Concept models and screenshots.**
   - Build a low-poly proof of concept per variation; it only needs to show the direction.
   - Shoot each from several angles with a photographer's intent, and caption every image with what it shows. Typical set:
     - a three-quarter hero shot
     - a silhouette or profile view
     - a detail or use-angle shot from a player's first-person height
     - an in-context shot in dark water with fog, under white and red light
   - Add a person-sized figure where scale isn't obvious.
   - Name images `<asset>_var<N>_img<M>.png`, e.g. `porthole_var2_img3.png`.
5. **Attach and review.**
   - GitHub's API can't upload attachments, so commit the PNGs to `concepts/<asset>/` (with a `.gdignore`) and embed them by commit-SHA permalink: `https://github.com/tsebens/silent_water/blob/<sha>/concepts/<asset>/<file>.png?raw=true`.
   - SHA links keep working after the files are deleted.
   - Move the issue to **In review**, then pick up the next issue.
6. **Review outcome.**
   - **Feedback:** the reviewer moves the issue back to Ready with notes, and it gets reworked when picked up.
   - **A variation is chosen:** the choice must be stated on the issue. Then delete the unchosen concept models and images (the issue's images survive through the SHA links). Move the issue back to In progress and build the finished model.
7. **Final model.**
   - Deliver it in `assets/models/<asset>/`:
     - the generating script
     - the exported model (`.glb`)
     - a `.tscn` that instances it with materials set up
   - Check that it imports and renders in Godot, post final screenshots, and move the issue to **In review**.
   - On approval it goes to **Done** and the issue is closed.

**Never close an issue** before the reviewer has chosen a variation and that choice is recorded on the issue.

### Problems and inefficiencies

Whenever something goes wrong or the workflow is slow, note it on that asset's issue: a tool limit, slow renders, unclear requests, a missing reference. These notes are reviewed periodically to adjust the workflow, and this file is updated with the outcome.

## Planned changes

- After `claude/serene-dijkstra-pnr9gr` merges, concept art moves to the agreed long-term home and the reference media is read from `main`.
