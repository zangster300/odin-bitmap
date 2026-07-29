package bitmap

import "core:testing"
import "core:thread"

set_alternating_bits :: proc(bitmap: ^Concurrent_Bitmap, first_bit: int) {
	for bit_index := first_bit; bit_index < concurrent_bit_len(bitmap); bit_index += 2 {
		concurrent_set(bitmap, bit_index, true)
	}
}

@(test)
test_bit_operations :: proc(t: ^testing.T) {
	value := u8(0)
	value = set_bit(value, 0, true)
	testing.expect_value(t, value, u8(1))
	testing.expect(t, get_bit(value, 0))

	value = set_bit(value, 0, false)
	testing.expect_value(t, value, u8(0))
	testing.expect(t, !get_bit(value, 0))

	set_bit_ref(&value, 7, true)
	testing.expect_value(t, value, u8(0x80))
}

@(test)
test_bitmap_length_and_storage :: proc(t: ^testing.T) {
	bitmap := bitmap_make(50)
	defer bitmap_destroy(&bitmap)

	testing.expect_value(t, len(bitmap_data(bitmap)), 7)
	testing.expect_value(t, bitmap_bit_len(bitmap), 56)

	for bit_index in 0 ..< bitmap_bit_len(bitmap) {
		testing.expect(t, !bitmap_get(bitmap, bit_index))
		bitmap_set(bitmap, bit_index, true)
	}

	for bit_index := bitmap_bit_len(bitmap) - 1; bit_index >= 0; bit_index -= 1 {
		testing.expect(t, bitmap_get(bitmap, bit_index))
		bitmap_set(bitmap, bit_index, false)
	}

	for bit_index in 0 ..< bitmap_bit_len(bitmap) {
		testing.expect(t, !bitmap_get(bitmap, bit_index))
	}
}

@(test)
test_length_rounding :: proc(t: ^testing.T) {
	requested := [?]int{0, 1, 7, 8, 9, 31, 32, 33}
	expected_bytes := [?]int{0, 1, 1, 1, 2, 4, 4, 5}

	for bit_count, index in requested {
		bitmap := bitmap_make(bit_count)
		testing.expect_value(t, len(bitmap_data(bitmap)), expected_bytes[index])
		testing.expect_value(t, bitmap_bit_len(bitmap), expected_bytes[index] * 8)
		bitmap_destroy(&bitmap)

		concurrent := concurrent_make(bit_count)
		testing.expect_value(t, concurrent_bit_len(&concurrent), expected_bytes[index] * 8)
		testing.expect_value(t, len(concurrent.words), (expected_bytes[index] + 3) / 4)
		concurrent_destroy(&concurrent)
	}
}

@(test)
test_bitmap_borrow_and_clone :: proc(t: ^testing.T) {
	data := []u8{1, 0, 0, 0, 0}

	borrowed := bitmap_borrow(data)
	bitmap_set(borrowed, 1, true)
	testing.expect_value(t, data[0], u8(3))
	bitmap_destroy(&borrowed)
	testing.expect_value(t, data[0], u8(3))

	cloned := bitmap_clone(data)
	defer bitmap_destroy(&cloned)
	bitmap_set(cloned, 0, false)
	testing.expect_value(t, data[0], u8(3))

	copy := bitmap_clone_data(cloned)
	defer delete(copy)
	copy[0] = 0xff
	testing.expect_value(t, bitmap_data(cloned)[0], u8(2))
}

@(test)
test_thread_safe_bitmap :: proc(t: ^testing.T) {
	bitmap := thread_safe_make(50)
	defer thread_safe_destroy(bitmap)

	thread_safe_set(bitmap, 30, true)
	testing.expect(t, thread_safe_get(bitmap, 30))
	testing.expect_value(t, thread_safe_bit_len(bitmap), 56)

	snapshot := thread_safe_clone_data(bitmap)
	defer delete(snapshot)
	testing.expect(t, get_bit(snapshot[30 / 8], 30 % 8))
}

@(test)
test_thread_safe_borrow :: proc(t: ^testing.T) {
	data := []u8{0, 0}
	first := thread_safe_borrow(data)
	second := thread_safe_borrow(data)
	defer thread_safe_destroy(first)
	defer thread_safe_destroy(second)

	thread_safe_set(first, 4, true)
	testing.expect(t, thread_safe_get(second, 4))
	thread_safe_set(second, 4, false)
	testing.expect(t, !thread_safe_get(first, 4))
}

@(test)
test_atomic_words :: proc(t: ^testing.T) {
	words := make([]u32, 100)
	defer delete(words)

	testing.expect(t, !atomic_words_get(words, 32))
	atomic_words_set(words, 32, true)
	testing.expect(t, atomic_words_get(words, 32))
	atomic_words_set(words, 32, false)
	testing.expect(t, !atomic_words_get(words, 32))
}

@(test)
test_concurrent_bitmap :: proc(t: ^testing.T) {
	bitmap := concurrent_make(10)
	defer concurrent_destroy(&bitmap)

	testing.expect_value(t, concurrent_bit_len(&bitmap), 16)
	testing.expect_value(t, len(bitmap.words), 1)

	concurrent_set(&bitmap, 3, true)
	concurrent_set(&bitmap, 12, true)
	testing.expect(t, concurrent_get(&bitmap, 3))
	testing.expect(t, concurrent_get(&bitmap, 12))

	snapshot := concurrent_clone_data(&bitmap)
	defer delete(snapshot)
	testing.expect_value(t, len(snapshot), 2)
	testing.expect(t, get_bit(snapshot[0], 3))
	testing.expect(t, get_bit(snapshot[1], 4))

	view := concurrent_data_unsafe(&bitmap)
	testing.expect_value(t, len(view), 2)
	testing.expect(t, get_bit(view[0], 3))
	testing.expect(t, get_bit(view[1], 4))
}

@(test)
test_concurrent_writers :: proc(t: ^testing.T) {
	bitmap := concurrent_make(128)
	defer concurrent_destroy(&bitmap)

	even := thread.create_and_start_with_poly_data2(&bitmap, 0, set_alternating_bits)
	odd := thread.create_and_start_with_poly_data2(&bitmap, 1, set_alternating_bits)
	defer if even != nil {thread.destroy(even)}
	defer if odd != nil {thread.destroy(odd)}

	if !testing.expect(t, even != nil && odd != nil, "could not create worker threads") {
		return
	}
	thread.join_multiple(even, odd)

	for bit_index in 0 ..< concurrent_bit_len(&bitmap) {
		testing.expect(t, concurrent_get(&bitmap, bit_index))
	}
}
