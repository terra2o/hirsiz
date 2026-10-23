package core

// calculates field of view from (start_x, start_y) within max_radius
// updates visible and explored arrays in dungeon
compute_fov :: proc(d: ^Dungeon, start_x, start_y: int, radius: int = 8) {
	for i in 0 ..< len(d.visible) {
		d.visible[i] = false
	}

	if !dungeon_in_bounds(d, start_x, start_y) do return

	idx := start_y * d.width + start_x
	d.visible[idx] = true
	d.explored[idx] = true

	radius_sq := radius * radius

	for dx in -radius ..= radius {
		cast_ray(d, start_x, start_y, start_x + dx, start_y - radius, radius_sq)
		cast_ray(d, start_x, start_y, start_x + dx, start_y + radius, radius_sq)
	}
	for dy in -radius ..= radius {
		cast_ray(d, start_x, start_y, start_x - radius, start_y + dy, radius_sq)
		cast_ray(d, start_x, start_y, start_x + radius, start_y + dy, radius_sq)
	}
}

@(private = "file")
cast_ray :: proc(d: ^Dungeon, x0, y0, x1, y1: int, max_dist_sq: int) {
	dx := abs(x1 - x0)
	dy := abs(y1 - y0)

	sx := x0 < x1 ? 1 : -1
	sy := y0 < y1 ? 1 : -1

	err := dx - dy
	x := x0
	y := y0

	for {
		dist_sq := (x - x0) * (x - x0) + (y - y0) * (y - y0)
		if dist_sq > max_dist_sq do break

		if dungeon_in_bounds(d, x, y) {
			idx := y * d.width + x
			d.visible[idx] = true
			d.explored[idx] = true

			if !d.tiles[idx].transparent && !(x == x0 && y == y0) {
				break
			}
		} else {
			break
		}

		if x == x1 && y == y1 do break

		e2 := 2 * err
		if e2 > -dy {
			err -= dy
			x += sx
		}
		if e2 < dx {
			err += dx
			y += sy
		}
	}
}
