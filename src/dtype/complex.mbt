// One complex element (plan v0.2 §6 S1). A single struct serves both
// complex64 and complex128: the components are MoonBit `Double` (64-bit,
// AGENTS.md §4), which holds a complex128 half exactly and a complex64 half
// (float32) losslessly. Naming it `Complex` rather than `Complex64`/`Complex128`
// keeps the element type out of the way of the `DType::Complex64` /
// `DType::Complex128` variants that tag which width the bytes came from.
//
// re/im are deliberately distinct fields, and the Oracle fixtures use
// im = 2 * re: a swapped read fails equality immediately instead of silently
// transposing the array.

///|
pub(all) struct Complex {
  re : Double
  im : Double
} derive(Debug, Eq)
