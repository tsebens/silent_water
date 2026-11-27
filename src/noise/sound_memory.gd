class_name SoundMemory
extends RefCounted
## A listener's record of one detection. Fades on the listener's own clock.

var position: Vector3 = Vector3.ZERO
## Listener-clock time the memory was made (s).
var time: float = 0.0
var intensity: float = 0.0
var kind: StringName = &""
var uncertainty: float = 0.0


static func from_event(event: SoundEvent, now: float) -> SoundMemory:
	var m: SoundMemory = SoundMemory.new()
	m.position = event.perceived_position
	m.time = now
	m.intensity = event.intensity
	m.kind = event.kind
	m.uncertainty = event.uncertainty
	return m


## Fading store. The caller passes its own clock to every call.
class Store extends RefCounted:
	## Seconds until a memory is dropped.
	var lifetime: float = 20.0
	var memories: Array[SoundMemory] = []

	func add(event: SoundEvent, now: float) -> SoundMemory:
		var m: SoundMemory = SoundMemory.from_event(event, now)
		memories.append(m)
		return m

	## 1 when fresh, 0 at [member lifetime].
	func freshness(m: SoundMemory, now: float) -> float:
		return clampf(1.0 - (now - m.time) / lifetime, 0.0, 1.0)

	## Intensity weighted toward the recent.
	func weight(m: SoundMemory, now: float) -> float:
		return m.intensity * freshness(m, now)

	func prune(now: float) -> void:
		for i: int in range(memories.size() - 1, -1, -1):
			if now - memories[i].time >= lifetime:
				memories.remove_at(i)

	## The memory with the highest weight, or null.
	func loudest(now: float) -> SoundMemory:
		prune(now)
		var best: SoundMemory = null
		var best_w: float = 0.0
		for m: SoundMemory in memories:
			var w: float = weight(m, now)
			if w > best_w:
				best_w = w
				best = m
		return best

	func clear() -> void:
		memories.clear()
