# bitmap

An allocator-aware Odin bitmap package with plain, mutex-protected, and atomic representations.

## Basic bitmap

```odin
package example

import bitmap "bitmap"

main :: proc() {
	bits := bitmap.bitmap_make(50)
	defer bitmap.bitmap_destroy(&bits)

	bitmap.bitmap_set(bits, 30, true)
	assert(bitmap.bitmap_get(bits, 30))
	assert(bitmap.bitmap_bit_len(bits) == 56)
}
```

Bits use least-significant-bit-first ordering within each byte. Requested lengths are rounded up to whole bytes, matching the storage semantics of the source package.

## Choosing a bitmap

| Type | Synchronization | Use when |
| --- | --- | --- |
| `Bitmap` | None | Access is single-threaded or synchronized by the caller. |
| `Thread_Safe_Bitmap` | One read/write mutex | You need a globally consistent snapshot, existing byte storage, or a whole-bitmap lock. |
| `Concurrent_Bitmap` | Atomic `u32` operations | Multiple threads frequently read or update independent bits. |

`Thread_Safe_Bitmap` permits multiple readers, but a writer blocks every other operation. Construct it with `thread_safe_make`, `thread_safe_clone`, or `thread_safe_borrow`, and release the returned pointer with `thread_safe_destroy`.

`Concurrent_Bitmap` avoids a bitmap-wide mutex. Each bit operation is atomic, but a sequence of operations is not one transaction, and a snapshot is only consistent one word at a time.

## Concurrent example

```odin
bits := bitmap.concurrent_make(128)
defer bitmap.concurrent_destroy(&bits)

bitmap.concurrent_set(&bits, 42, true)
assert(bitmap.concurrent_get(&bits, 42))
```

Use `concurrent_clone_data` for a snapshot. `concurrent_data_unsafe` directly exposes the backing bytes and must not be accessed while another thread updates the bitmap.

## Ack

Heavily inspired by [go-bitmap](https://github.com/boljen/go-bitmap)
