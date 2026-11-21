class_name SiteConstraint
extends Resource
## Base class for a rule a dive site must satisfy (a flat pad for an objective,
## a clear lane, a hiding place). No concrete kinds yet: they extend this and
## are listed in [member SiteSpec.constraints].

## Short label for the terrain lab and logs.
@export var label: String = ""
