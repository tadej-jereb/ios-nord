"""Per-image card for the H/F series: what it changes, what a park proves, what is next.

One entry per target, so the builder, the recipe card and the expected/observed table
cannot drift apart. `exp` is the signature that must be observed; `next` is the single
line that changes if the image is refused.
"""

CARDS = {
    'h1': dict(
        code0='+0x2480000', exp='park: off fastboot, off adb >= 90 s',
        why="stock's first page (header AND stub) byte for byte; our 8-byte park at stock's "
            "own branch landing 0x2480000",
        proves='page-0 byte identity is sufficient to be entered, and the landing offset in '
               'stock\'s code0 is what the ABL actually honours',
        kills='H-entry-1/2/4 (nothing about our page 0 matters) and confirms the branch '
              'decode; if it parks, the fault is in the body/layout, not the entry',
        next='if refused: page 0 identity is not enough -> the fault is the section layout or '
             'weight -> run H3/H4, then F-series'),
    'h1x': dict(
        code0='+0x2480000 (park sits at 0x92000)', exp='refused, or a udf/die, never a park',
        why='brief-literal H1: stock page 0 verbatim but the park at 0x92000 instead of the '
            'real landing',
        proves='the imm26 field is words, not bytes: stock branches to +0x2480000',
        kills='the premise that the landing is +0x92000',
        next='nothing changes; it is the arithmetic control for H1'),
    'h2': dict(
        code0='+0x800', exp='park, or refused',
        why="our own 0..0x40 Image header, stock bytes 0x40..0x1000, park at our code0's "
            "destination 0x800",
        proves='with H1: a park at H1 and a refusal here localises the fault to our header '
               'fields 0..0x40; a park here too exonerates the header and points at the body',
        kills='H-entry-3/4 (stub alignment) and, with H1, splits header from stub',
        next='if refused while H1 parks: go to F1/F2/F3 to name the field'),
    'h3': dict(
        code0='+0x92000', exp='park at a far offset, text_offset 0x80000',
        why="our image verbatim, kernel padded to 0x92000, park there, code0 far branch, "
            "text_offset 0x80000, image_size 0x93000",
        proves='a far landing with a truthful image_size works, i.e. the ABL honours '
               'text_offset/image_size instead of requiring a near entry',
        kills='H-entry-1 (fixed near entry) and H-entry-5 (image_size not consulted)',
        next='if refused: entry distance or text_offset handling -> H4, then F1'),
    'h4': dict(
        code0='+0x80000', exp='park, entry exactly at base+text_offset',
        why='our image verbatim, park at 0x80000, code0 branch there, text_offset 0x80000',
        proves='the ABL enters at base+text_offset (0x8000+0x80000) rather than at the image '
               'base, so code that assumes base+0 is 0x80000 away from where it runs',
        kills='H-entry-2 (entered at image base) as the design assumption',
        next='if refused while H3 parks: text_offset 0x80000 vs the branch target is the '
             'variable -> F1 with the same park position'),
    'f1': dict(
        code0='+0x2480000', exp='park',
        why='H1 with exactly one field from our header: text_offset 0 (stock 0x80000)',
        proves='text_offset 0 is harmless',
        kills='H-entry-3 (text_offset semantics)',
        next='if refused: text_offset is the offending field; pack text_offset 0x80000'),
    'f2': dict(
        code0='+0x2480000', exp='park',
        why='H1 with exactly one field from our header: image_size 0x4d000 (stock 0x33b7000)',
        proves='a small image_size is harmless even with 36 MB of body behind it',
        kills='H-entry-5 (image_size is sanity-checked against load extent)',
        next='if refused: image_size is the offending field; set it to the real extent'),
    'f3': dict(
        code0='+0x800', exp='park',
        why='H1 with exactly one field from our header: code0 = b +0x800, park moved there',
        proves='a near branch to 0x800 is harmless (stub alignment is stock\'s anyway)',
        kills='H-entry-4 (entry must be stock\'s exact branch shape)',
        next='if refused: code0 distance itself is checked; move the park to 0x2480000'),
}

ORDER = ['h1', 'h1x', 'h2', 'h3', 'h4', 'f1', 'f2', 'f3']
