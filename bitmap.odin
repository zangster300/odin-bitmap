package bitmap

import "base:runtime"
import "core:slice"
import "core:sync"

@(private = "file", rodata)
SET_MASKS: [8]u8 = {1, 2, 4, 8, 16, 32, 64, 128}

@(private = "file", rodata)
CLEAR_MASKS: [8]u8 = {254, 253, 251, 247, 239, 223, 191, 127}

/*
Bitmap is a compact, mutable collection of boolean flags addressed by integer
bit index. It is useful for occupancy maps, visited sets, feature flags, and
other cases where storing one byte per flag would be wasteful.

Bitmap does not synchronize access. Use it from one thread or provide external
synchronization. Use Thread_Safe_Bitmap when an entire bitmap must be protected
by one lock, or Concurrent_Bitmap for frequent independent atomic bit updates.

Bits use least-significant-bit-first numbering within each byte: bit zero is the
least-significant bit of bytes[0], bit seven is its most-significant bit, and bit
eight is the least-significant bit of bytes[1]. The host's byte endianness does
not affect this []u8 layout.

A Bitmap returned by bitmap_make or bitmap_clone owns its storage. Release that
storage with bitmap_destroy. A value returned by bitmap_borrow only views memory
owned by its caller.
*/
Bitmap :: struct {
	bytes:     []u8,
	allocator: runtime.Allocator,
	owned:     bool,
}

/*
Thread_Safe_Bitmap protects an entire Bitmap with one read/write mutex. Multiple
readers may access it together, while a writer excludes every other operation.
Use it when whole-bitmap coordination, a globally consistent snapshot, or a
mutex-protected view over existing byte storage is more important than the cost
of locking each operation.

Each public operation acquires and releases the lock independently. A sequence
such as get followed by set is not one atomic transaction.

Values of this type must not be copied after their first use. Constructors
return a pointer so the mutex retains a stable address.
*/
Thread_Safe_Bitmap :: struct {
	bitmap:    Bitmap,
	mutex:     sync.RW_Mutex,
	allocator: runtime.Allocator,
}

@(private)
byte_count_for_bits :: #force_inline proc(bit_count: int) -> int {
	assert(bit_count >= 0, "bitmap length cannot be negative")
	return bit_count / 8 + (1 if bit_count % 8 != 0 else 0)
}

/*
bitmap_make creates a zero-initialized bitmap large enough for bit_count bits.
Its observable length is rounded up to a whole byte.
*/
bitmap_make :: proc(bit_count: int, allocator := context.allocator) -> Bitmap {
	byte_count := byte_count_for_bits(bit_count)
	return {
		bytes     = make([]u8, byte_count, allocator),
		allocator = allocator,
		owned     = true,
	}
}

// bitmap_borrow creates a non-owning view over data.
bitmap_borrow :: proc(data: []u8) -> Bitmap {
	return {
		bytes = data,
		owned = false,
	}
}

// bitmap_clone copies data into a new owning bitmap.
bitmap_clone :: proc(data: []u8, allocator := context.allocator) -> Bitmap {
	return {
		bytes     = slice.clone(data, allocator),
		allocator = allocator,
		owned     = true,
	}
}

// bitmap_destroy releases owned storage and resets bitmap to its zero value.
bitmap_destroy :: proc(bitmap: ^Bitmap) {
	if bitmap.owned {
		delete(bitmap.bytes, bitmap.allocator)
	}
	bitmap^ = {}
}

// bitmap_data returns the bitmap's underlying storage without copying it.
bitmap_data :: proc(bitmap: Bitmap) -> []u8 {
	return bitmap.bytes
}

// bitmap_clone_data returns an independently owned copy of the bitmap's bytes.
bitmap_clone_data :: proc(bitmap: Bitmap, allocator := context.allocator) -> []u8 {
	return slice.clone(bitmap.bytes, allocator)
}

// bitmap_bit_len returns the storage length in bits, always a multiple of eight.
bitmap_bit_len :: #force_inline proc(bitmap: Bitmap) -> int {
	return len(bitmap.bytes) * 8
}

// bitmap_get returns the bit at bit_index.
bitmap_get :: #force_inline proc(bitmap: Bitmap, bit_index: int) -> bool {
	assert(0 <= bit_index && bit_index < bitmap_bit_len(bitmap), "bitmap bit index out of bounds")
	return get_bit(bitmap.bytes[bit_index / 8], bit_index % 8)
}

// bitmap_set changes the bit at bit_index to value.
bitmap_set :: #force_inline proc(bitmap: Bitmap, bit_index: int, value: bool) {
	assert(0 <= bit_index && bit_index < bitmap_bit_len(bitmap), "bitmap bit index out of bounds")
	byte_index := bit_index / 8
	bitmap.bytes[byte_index] = set_bit(bitmap.bytes[byte_index], bit_index % 8, value)
}

// get_bit returns the indexed bit of value.
get_bit :: #force_inline proc(value: u8, bit_index: int) -> bool {
	assert(0 <= bit_index && bit_index < 8, "byte bit index out of bounds")
	return value & SET_MASKS[bit_index] != 0
}

// set_bit returns value with the indexed bit changed to bit_value.
set_bit :: #force_inline proc(value: u8, bit_index: int, bit_value: bool) -> u8 {
	assert(0 <= bit_index && bit_index < 8, "byte bit index out of bounds")
	if bit_value {
		return value | SET_MASKS[bit_index]
	}
	return value & CLEAR_MASKS[bit_index]
}

// set_bit_ref changes the indexed bit in place.
set_bit_ref :: #force_inline proc(value: ^u8, bit_index: int, bit_value: bool) {
	value^ = set_bit(value^, bit_index, bit_value)
}

/*
thread_safe_make allocates a zero-initialized, mutex-protected bitmap.
Release it with thread_safe_destroy.
*/
thread_safe_make :: proc(bit_count: int, allocator := context.allocator) -> ^Thread_Safe_Bitmap {
	result := new(Thread_Safe_Bitmap, allocator)
	result.bitmap = bitmap_make(bit_count, allocator)
	result.allocator = allocator
	return result
}

/*
thread_safe_clone allocates a mutex-protected bitmap containing a copy of data.
*/
thread_safe_clone :: proc(data: []u8, allocator := context.allocator) -> ^Thread_Safe_Bitmap {
	result := new(Thread_Safe_Bitmap, allocator)
	result.bitmap = bitmap_clone(data, allocator)
	result.allocator = allocator
	return result
}

/*
thread_safe_borrow allocates a mutex-protected, non-owning view over data.
The caller must keep data alive until the returned bitmap is destroyed.
*/
thread_safe_borrow :: proc(data: []u8, allocator := context.allocator) -> ^Thread_Safe_Bitmap {
	result := new(Thread_Safe_Bitmap, allocator)
	result.bitmap = bitmap_borrow(data)
	result.allocator = allocator
	return result
}

/*
thread_safe_destroy releases the bitmap and its wrapper. The caller must ensure
that no other thread is using bitmap.
*/
thread_safe_destroy :: proc(bitmap: ^Thread_Safe_Bitmap) {
	if bitmap == nil {
		return
	}
	allocator := bitmap.allocator
	bitmap_destroy(&bitmap.bitmap)
	free(bitmap, allocator)
}

// thread_safe_bit_len returns the bitmap's storage length in bits.
thread_safe_bit_len :: proc(bitmap: ^Thread_Safe_Bitmap) -> int {
	sync.rw_mutex_shared_lock(&bitmap.mutex)
	defer sync.rw_mutex_shared_unlock(&bitmap.mutex)
	return bitmap_bit_len(bitmap.bitmap)
}

// thread_safe_get returns the indexed bit while holding a shared lock.
thread_safe_get :: proc(bitmap: ^Thread_Safe_Bitmap, bit_index: int) -> bool {
	sync.rw_mutex_shared_lock(&bitmap.mutex)
	defer sync.rw_mutex_shared_unlock(&bitmap.mutex)
	return bitmap_get(bitmap.bitmap, bit_index)
}

// thread_safe_set changes the indexed bit while holding an exclusive lock.
thread_safe_set :: proc(bitmap: ^Thread_Safe_Bitmap, bit_index: int, value: bool) {
	sync.rw_mutex_lock(&bitmap.mutex)
	defer sync.rw_mutex_unlock(&bitmap.mutex)
	bitmap_set(bitmap.bitmap, bit_index, value)
}

/*
thread_safe_clone_data takes a consistent snapshot of the bitmap. The caller
owns the returned slice.
*/
thread_safe_clone_data :: proc(
	bitmap: ^Thread_Safe_Bitmap,
	allocator := context.allocator,
) -> []u8 {
	sync.rw_mutex_shared_lock(&bitmap.mutex)
	defer sync.rw_mutex_shared_unlock(&bitmap.mutex)
	return bitmap_clone_data(bitmap.bitmap, allocator)
}

/*
thread_safe_data_unsafe exposes the underlying byte slice.

The view becomes unsafe to read or write as soon as another thread can access
the bitmap. Prefer thread_safe_clone_data for a stable snapshot.
*/
thread_safe_data_unsafe :: proc(bitmap: ^Thread_Safe_Bitmap) -> []u8 {
	sync.rw_mutex_shared_lock(&bitmap.mutex)
	defer sync.rw_mutex_shared_unlock(&bitmap.mutex)
	return bitmap_data(bitmap.bitmap)
}
