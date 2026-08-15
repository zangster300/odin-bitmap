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

## Ownership and borrowing

Values returned by `bitmap_make`, `bitmap_clone`, `concurrent_make`, and `concurrent_clone` own their storage and must be destroyed exactly once. They are shallow handles: use `bitmap_clone` or `concurrent_clone` when an independent lifetime is needed instead of copying an owning value.

`bitmap_borrow` and `thread_safe_borrow` do not own the supplied bytes. The caller must keep those bytes alive. A `Thread_Safe_Bitmap` only synchronizes operations made through that particular wrapper; direct access to the borrowed slice or access through a second wrapper must not occur concurrently.

## Choosing a bitmap

| Type | Synchronization | Use when |
| --- | --- | --- |
| `Bitmap` | None | Access is single-threaded or synchronized by the caller. |
| `Thread_Safe_Bitmap` | One read/write mutex | You need a globally consistent snapshot, existing byte storage, or a whole-bitmap lock. |
| `Concurrent_Bitmap` | Atomic `u32` operations | Multiple threads frequently read or update independent bits. |

`Thread_Safe_Bitmap` permits multiple readers, but a writer blocks every other operation. Construct it with `thread_safe_make`, `thread_safe_clone`, or `thread_safe_borrow`, and release the returned pointer with `thread_safe_destroy`.

`Concurrent_Bitmap` avoids a bitmap-wide mutex. Each bit operation is atomic, but a sequence of operations is not one transaction, and a snapshot is only consistent one word at a time.

Construct one with `concurrent_make`, or use `concurrent_clone` to copy an existing byte layout into aligned atomic storage. There is intentionally no concurrent borrowing operation because an arbitrary byte slice cannot guarantee the alignment required by atomic `u32` operations.

## Concurrent example

```odin
bits := bitmap.concurrent_make(128)
defer bitmap.concurrent_destroy(&bits)

bitmap.concurrent_set(&bits, 42, true)
assert(bitmap.concurrent_get(&bits, 42))
```

Use `concurrent_clone_data` for a snapshot. `thread_safe_data_unsafe` and `concurrent_data_unsafe` directly expose backing bytes and must only be used when the caller can guarantee exclusive access.

## Ack

Heavily inspired by [go-bitmap](https://github.com/boljen/go-bitmap)
