class_name UITheme
extends RefCounted
## One palette for every piece of UI, so the menus, HUD and touch controls match.
## Warm sand and coral against deep sea navy — the colours of the game itself.

# Surfaces
const PANEL        := Color(0.047, 0.090, 0.161, 0.95)  # deep navy glass
const PANEL_SOLID  := Color(0.059, 0.110, 0.192, 1.0)
const RAISED       := Color(0.094, 0.165, 0.259, 1.0)   # list rows, wells
const SCRIM        := Color(0.016, 0.035, 0.070, 0.78)  # behind modals

# Brand
const PRIMARY      := Color(0.106, 0.600, 0.651)        # teal — normal buttons
const PRIMARY_HI   := Color(0.145, 0.722, 0.776)
const PRIMARY_LO   := Color(0.067, 0.439, 0.486)
const ACCENT       := Color(1.000, 0.510, 0.247)        # coral — main action
const ACCENT_HI    := Color(1.000, 0.620, 0.380)
const ACCENT_LO    := Color(0.820, 0.380, 0.157)

# Text
const TEXT         := Color(0.949, 0.973, 0.988)
const TEXT_DIM     := Color(0.639, 0.714, 0.784)
const TEXT_WARM    := Color(1.000, 0.953, 0.855)
const GOLD         := Color(1.000, 0.804, 0.290)        # coins
const DANGER       := Color(0.937, 0.325, 0.314)
const GOOD         := Color(0.329, 0.808, 0.510)

# Rarity
const RARITY := {
	"Common": Color(0.820, 0.863, 0.898),
	"Uncommon": Color(0.329, 0.808, 0.510),
	"Rare": Color(0.329, 0.639, 1.000),
	"Epic": Color(0.741, 0.447, 1.000),
	"Legendary": Color(1.000, 0.714, 0.247),
}


## A rounded panel/button background.
static func box(color: Color, radius := 18, pad_x := 26, pad_y := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


## Same, with a subtle top highlight border.
static func box_edged(color: Color, edge: Color, radius := 18) -> StyleBoxFlat:
	var s := box(color, radius)
	s.set_border_width_all(2)
	s.border_color = edge
	return s
