---
name: Facility brief
about: A facility (a building, tunnel, docking arm or whole site) for the pipeline to build (docs/asset_process.md, section 10)
title: "Concept: <facility>"
labels: []
---

<!--
The brief is the whole input. Commit the concept images and the floorplan program to the repo first: agents cannot
fetch images attached to an issue. Label the issue `concept` when the text is final. The pipeline breaks it down and
builds it, then shows you the finished facility under sea light for look approval before the pull request
(docs/asset_process.md, 6.5 and 10). Worked example: assets/models/facilities/research_station/program.yaml
-->

## Summary

<What the facility is and who it was built for, in the art direction's words, and its class (design doc, "Facilities"). Two to four sentences.>

## Brief

```yaml
facility: <slug>
class: <facility class from the design doc, "Facilities">

concept:                      # the look and the arrangement, NOT the room list
  images:
    - path: assets/models/<...>/concept/<image>.png
      role: primary           # primary = the thing to build; context = where it sits
      view: <where the viewer stands>
      camera: <greybox camera name>   # e.g. chasm_approach, overview: the review renders from here, beside this image
  doc: <path to a concept doc, if any>
  compare_on:                 # what the review may judge
    - overall massing and silhouette
    - <the tier, struts, buttress fins, window bands, neon placement, the docking arm ...>
    # Name only things the facility contains.
  ignore:                     # differences the review must not flag
    - lighting mood, fog, sea life
    - the sub's detail
    - room contents, people, surroundings

program: assets/models/facilities/<slug>/program.yaml   # authoritative for layout: rooms, doors, tunnels, zones, routes

functions:                    # authoritative: objective anchors and systems
  - id: <name>
    kind: <objective | power | life_support | bilges | comms | dock>
    anchor: <room or door id in the program>
    binds: <script or system it connects to, if known>
    status: <implemented | anchor only, the function is not implemented yet>   # checked against the code

constraints:
  frame: site frame: ground at Y=0, X along the ledge, the chasm toward -Z
  triangle_budget: 60000      # per structure scene; facility_parts scenes are 2000
  ground: <where each structure stands: ledge, cliff face, ...>
  overhangs: <each declared overhang and what supports it, e.g. the docking arm and its struts>
  sub_envelope: <the sub at the dock: 10 x 3.8 x 3 m plus the tower, hatch on the collar, approach from the chasm>
```

## Out of scope

<Usually: door behaviours, placing the facility in a dive site, and any game behaviour the functions above don't have yet.>
