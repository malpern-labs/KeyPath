# Metal snapshot reference storage

The five entrance reference PNGs retain the complete 1800×1040 Metal render,
all five checkpoints, original PNG metadata and original comparison tolerances.
Only the lossless IDAT zlib compression changed (level 9, concatenated IDAT).
No quantization, resize, filter transformation or pixel editing was performed.

November 19 verification compared every non-IDAT chunk with the git reference
and decompressed both original and replacement IDAT streams. Every byte matched.
The reference total decreased from 8,596,775 to 6,127,327 bytes
(28.7% smaller; 2,469,448 bytes saved).

Use the existing Metal snapshot test for renderer behavior. Lossless storage
optimization does not justify lowering resolution or weakening tolerances.
Newly recorded goldens can be recompressed the same way after preserving an
original copy and verifying PNG CRCs, metadata and decompressed scanline equality.
