extends TestCase
## Felled trees and broken rock grow back after a while of play, but never
## in front of her.


func test_regrowth() -> void:
	var w := OpenWorld.new()
	w.gen = TerrainGen.new(1337)
	w.focus = Vector3(1000, 0, 1000)
	w.removed = {"0,0,3": 0.0, "0,0,4": 500.0, "15,15,2": 0.0}
	w.clock = 700.0
	w.regrow()
	check(not w.removed.has("0,0,3"), "long gone and far away: it grows back")
	check(w.removed.has("0,0,4"), "not yet: it was felled too recently")
	check(w.removed.has("15,15,2"), "right where she stands: it waits until she leaves")
	w.free()
