---
name: Station brief
about: A station or other composite asset for the pipeline to build (docs/asset_process.md)
title: "Concept: <station>"
labels: []
---

<!--
The brief is the whole input. Commit the concept images to the repo first: agents cannot fetch images attached to
an issue. Label the issue `concept` when the text is final; the breakdown comes back to you for approval before
anything is built. Worked example: assets/models/stations/sonar_console/brief.yaml
-->

## Summary

<What the station is and who uses it, in the art direction's words. Two to four sentences.>

## Brief

```yaml
station: <slug>

concept:                      # the look and the arrangement, NOT the control list
  images:
    - path: assets/models/<...>/concept/<image>.png
      role: primary           # primary = the thing to build; context = where it sits
      view: <where the viewer stands>
      camera: concept_<name>  # the review renders the station from here, beside this image
  doc: <path to a concept doc, if any>
  compare_on:                 # what the review may judge
    - overall massing and silhouette
    - <screen size, where controls sit and in what order, seat position, colour blocking ...>
  ignore:                     # differences the review must not flag
    - number, type and labels of controls (functions decides those)
    - screen content, lighting mood, people, surroundings

functions:                    # authoritative: one entry per real game function
  - id: <name>
    control: <what the operator touches>      # or display: / furniture:
    binds: <script or system it connects to, if known>
    status: <implemented | control only, the function is not implemented yet>

constraints:
  frame: floor at Y=0, back on Z=0, operator at +Z facing -Z
  seated_eye_height_m: 1.2
  reach_m: 0.75
  triangle_budget: 12000
```

## Out of scope

<Usually: placing the station in the sub, and any game behaviour the functions above don't have yet.>
