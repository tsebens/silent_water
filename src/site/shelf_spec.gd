class_name ShelfSpec
extends Resource
## One ledge cut into a canyon wall: a footprint (world metres) and the height
## its surface is flattened to.

## Horizontal footprint in world x/z; the AABB's y is unused by the terrain.
@export var footprint: AABB = AABB()
## World y of the ledge surface.
@export var top_y: float = -60.0
