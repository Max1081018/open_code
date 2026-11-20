class_name Inventory
extends RefCounted
## A fixed number of slots, each empty or holding a stack of one item.
##
## The first HOTBAR_SIZE slots are the hotbar. Pure data: no nodes, so it
## can be tested headlessly and saved as a plain array.

signal changed

const HOTBAR_SIZE := 8

var slots: Array = []  ## Each entry is null or {"id": String, "count": int}


func _init(size: int = 40) -> void:
	slots.resize(size)


func size() -> int:
	return slots.size()


func get_slot(index: int):
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


func count(id: String) -> int:
	var total := 0
	for slot in slots:
		if slot != null and slot.id == id:
			total += slot.count
	return total


func has_all(ingredients: Dictionary) -> bool:
	for id in ingredients:
		if count(id) < ingredients[id]:
			return false
	return true


## Add up to `amount`; returns how many did NOT fit.
func add(id: String, amount: int) -> int:
	if amount <= 0 or not Items.exists(id):
		return amount

	var limit := Items.stack_size(id)
	var left := amount

	# Top up existing stacks first, so pickups merge instead of scattering.
	for slot in slots:
		if left == 0:
			break
		if slot != null and slot.id == id and slot.count < limit:
			var moved: int = min(limit - slot.count, left)
			slot.count += moved
			left -= moved

	for i in slots.size():
		if left == 0:
			break
		if slots[i] == null:
			var moved: int = min(limit, left)
			slots[i] = {"id": id, "count": moved}
			left -= moved

	if left != amount:
		changed.emit()
	return left


## Whether `amount` of `id` would fit entirely.
func can_fit(id: String, amount: int) -> bool:
	var limit := Items.stack_size(id)
	var room := 0
	for slot in slots:
		if slot == null:
			room += limit
		elif slot.id == id:
			room += limit - slot.count
		if room >= amount:
			return true
	return false


## Remove `amount`; returns false (removing nothing) if there is not enough.
func remove(id: String, amount: int) -> bool:
	if count(id) < amount:
		return false

	var left := amount
	# Take from the end, so the hotbar is the last place a stack shrinks.
	for i in range(slots.size() - 1, -1, -1):
		if left == 0:
			break
		var slot = slots[i]
		if slot != null and slot.id == id:
			var taken: int = min(slot.count, left)
			slot.count -= taken
			left -= taken
			if slot.count == 0:
				slots[i] = null

	changed.emit()
	return true


func remove_at(index: int, amount: int = 1) -> void:
	var slot = get_slot(index)
	if slot == null:
		return
	slot.count -= amount
	if slot.count <= 0:
		slots[index] = null
	changed.emit()


## Swap two slots, or merge them if they hold the same item.
func move(from: int, to: int) -> void:
	if from == to:
		return
	var a = get_slot(from)
	var b = get_slot(to)
	if a != null and b != null and a.id == b.id:
		var limit := Items.stack_size(a.id)
		var moved: int = min(limit - b.count, a.count)
		b.count += moved
		a.count -= moved
		if a.count == 0:
			slots[from] = null
	else:
		slots[from] = b
		slots[to] = a
	changed.emit()


## The best item of `kind` held anywhere, by tier. Used for auto-tools.
func best_of_kind(kind: int) -> String:
	var best := ""
	var best_tier := -1
	for slot in slots:
		if slot == null:
			continue
		var d: Dictionary = Items.def(slot.id)
		if d.get("kind", -1) == kind and d.get("tier", 0) > best_tier:
			best = slot.id
			best_tier = d.get("tier", 0)
	return best


## Craft one batch of `recipe` if possible. Returns true on success.
func craft(recipe: Array) -> bool:
	var result: String = recipe[0]
	var amount: int = recipe[1]
	var ingredients: Dictionary = recipe[3]

	if not has_all(ingredients):
		return false

	# Check room *after* the ingredients would leave, so crafting from a
	# full bag still works when it frees the slot it needs.
	var snapshot := to_array()
	for id in ingredients:
		remove(id, ingredients[id])
	if not can_fit(result, amount):
		from_array(snapshot)
		return false

	add(result, amount)
	return true


func to_array() -> Array:
	var out := []
	for slot in slots:
		out.append(null if slot == null else {"id": slot.id, "count": slot.count})
	return out


func from_array(data: Array) -> void:
	var capacity: int = max(data.size(), slots.size())
	slots.clear()
	slots.resize(capacity)
	for i in data.size():
		var slot = data[i]
		if slot != null and Items.exists(str(slot.get("id", ""))):
			slots[i] = {"id": str(slot.id), "count": int(slot.count)}
	changed.emit()
