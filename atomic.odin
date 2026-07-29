package bitmap

import "base:runtime"
import "core:slice"
import "core:sync"

/*
Atomic_Bitmap_Words is a word-aligned bitmap representation suitable for Odin's
u32 atomic operations. It is the low-level storage used by Concurrent_Bitmap;
most callers should use Concurrent_Bitmap instead. Its length is
len(words) * 32 bits.
*/
Atomic_Bitmap_Words :: []u32

/*
Concurrent_Bitmap supports independent bit reads and writes from multiple
threads using atomic u32 operations instead of one bitmap-wide mutex. Use it for
high-frequency flags, worker state, allocation markers, and similar workloads
where threads usually operate on individual bits.

Each get or set is atomic, including competing updates to different bits in the
same word. A group of operations is not one transaction, and
concurrent_clone_data is consistent per word rather than across the entire
bitmap. Use Thread_Safe_Bitmap when a globally consistent snapshot or
whole-bitmap serialization for each operation is required.

The public length has byte granularity. Aligned u32 words provide the backing
storage, and unused high bits of the final word remain private padding.
*/
Concurrent_Bitmap :: struct {
	words:      Atomic_Bitmap_Words,
	byte_count: int,
	allocator:  runtime.Allocator,
}

@(private = "file")
concurrent_storage_bit_index :: #force_inline proc(bit_index: int) -> int {
	when ODIN_ENDIAN == .Little {
		return bit_index
	} else {
		word_index := bit_index / 32
		bit_in_word := bit_index % 32
		byte_in_word := bit_in_word / 8
		bit_in_byte := bit_in_word % 8
		return word_index * 32 + (3 - byte_in_word) * 8 + bit_in_byte
	}
}

// atomic_words_get atomically reads a bit from words.
atomic_words_get :: #force_inline proc(words: Atomic_Bitmap_Words, bit_index: int) -> bool {
	assert(0 <= bit_index && bit_index < len(words) * 32, "atomic bitmap bit index out of bounds")
	word := sync.atomic_load(&words[bit_index / 32])
	mask: u32 = u32(1) << uint(bit_index % 32)
	return word & mask != 0
}

// atomic_words_set atomically changes a bit in words.
atomic_words_set :: #force_inline proc(words: Atomic_Bitmap_Words, bit_index: int, value: bool) {
	assert(0 <= bit_index && bit_index < len(words) * 32, "atomic bitmap bit index out of bounds")
	word := &words[bit_index / 32]
	mask: u32 = u32(1) << uint(bit_index % 32)
	if value {
		_ = sync.atomic_or(word, mask)
	} else {
		_ = sync.atomic_and(word, ~mask)
	}
}

/*
concurrent_make creates a zero-initialized concurrent bitmap. Its observable
length is rounded up to a whole byte.
*/
concurrent_make :: proc(bit_count: int, allocator := context.allocator) -> Concurrent_Bitmap {
	byte_count := byte_count_for_bits(bit_count)
	word_count := (byte_count + 3) / 4
	return {
		words      = make([]u32, word_count, allocator),
		byte_count = byte_count,
		allocator  = allocator,
	}
}

// concurrent_destroy releases a concurrent bitmap's storage.
concurrent_destroy :: proc(bitmap: ^Concurrent_Bitmap) {
	delete(bitmap.words, bitmap.allocator)
	bitmap^ = {}
}

// concurrent_bit_len returns the observable storage length in bits.
concurrent_bit_len :: #force_inline proc(bitmap: ^Concurrent_Bitmap) -> int {
	return bitmap.byte_count * 8
}

// concurrent_get atomically reads the indexed bit.
concurrent_get :: #force_inline proc(bitmap: ^Concurrent_Bitmap, bit_index: int) -> bool {
	assert(
		0 <= bit_index && bit_index < concurrent_bit_len(bitmap),
		"concurrent bitmap bit index out of bounds",
	)
	return atomic_words_get(bitmap.words, concurrent_storage_bit_index(bit_index))
}

// concurrent_set atomically changes the indexed bit.
concurrent_set :: #force_inline proc(bitmap: ^Concurrent_Bitmap, bit_index: int, value: bool) {
	assert(
		0 <= bit_index && bit_index < concurrent_bit_len(bitmap),
		"concurrent bitmap bit index out of bounds",
	)
	atomic_words_set(bitmap.words, concurrent_storage_bit_index(bit_index), value)
}

/*
concurrent_clone_data returns a consistent per-word snapshot in the same byte
layout used by Bitmap. Updates to different words may occur between loads.
The caller owns the returned slice.
*/
concurrent_clone_data :: proc(bitmap: ^Concurrent_Bitmap, allocator := context.allocator) -> []u8 {
	result := make([]u8, bitmap.byte_count, allocator)
	for _, word_index in bitmap.words {
		word := sync.atomic_load(&bitmap.words[word_index])
		byte_offset := word_index * 4
		bytes_left := min(4, bitmap.byte_count - byte_offset)
		word_bytes := slice.bytes_from_ptr(&word, size_of(word))
		copy(result[byte_offset:byte_offset + bytes_left], word_bytes[:bytes_left])
	}
	return result
}

/*
concurrent_data_unsafe exposes the concurrent bitmap's underlying bytes without
copying. The view is valid until concurrent_destroy, but accessing it while
another thread updates the bitmap is unsafe. Prefer concurrent_clone_data.
*/
concurrent_data_unsafe :: proc(bitmap: ^Concurrent_Bitmap) -> []u8 {
	return slice.to_bytes(bitmap.words)[:bitmap.byte_count]
}
