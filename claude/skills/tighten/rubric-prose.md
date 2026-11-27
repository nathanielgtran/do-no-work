# tighten rubric for prose

Condensed from three MIT-licensed pstack skills (Lauren Tan; mirror backnotprop/pstack of
cursor/plugins/pstack), pinned 9 Oct 2026. Paraphrased; rule intent is theirs. Section A is
from unslop, B from technical-writing, C from principle-minimize-reader-load applied to
documents. `scripts/sync-check.sh` reports drift.

<!-- upstream: backnotprop/pstack skills/unslop/SKILL.md commit=c0c3f13cc58005cce7f28c1e6d7ccc439867f171 blob=229a090708710c36caa0017f8d33e90880dc6846 -->
<!-- upstream: backnotprop/pstack skills/technical-writing/SKILL.md commit=c0c3f13cc58005cce7f28c1e6d7ccc439867f171 blob=5eef4fc494a059eb740cb621dadb4a7a81af23e4 -->
<!-- upstream: backnotprop/pstack skills/principle-minimize-reader-load/SKILL.md commit=55bfdc262dd7f99254d19b53a96cf1dfb24c213b blob=64541d963123e344078d82fd3977e857e76129df -->

## Hard rules (override everything below)

- Never drop a fact, number, command, code block, link, file path, name or date. Cutting
  words is the job; cutting information is a defect. When unsure whether a line carries a
  fact, keep it.
- Preserve verbatim: YAML frontmatter, `[[wikilinks]]`, URLs, code fences and their
  contents, tables' data cells, quoted text, and anything inside backticks.
- Keep the author's voice: Australian English spelling, day-first dates (9 Oct 2026,
  9/10/2026), first person where the author used it, informal register where the author
  did. Tighten the sentence; do not rewrite the person.
- Never reorder sections; a `structure` finding is a proposal only, never auto-applied.
- A fix is a rewrite of the exact lines named, nothing else. Never add new claims.

## A. Slop and filler (unslop)

1. filler: "in order to" (to), "due to the fact that" (because), "it is important to note
   that" (delete), "basically", "essentially", "actually" doing no work.
2. slop vocabulary: additionally, crucial, delve, enhance, fostering, garner, interplay,
   intricate, landscape, pivotal, robust, seamless, showcase, tapestry, testament,
   underscore, vibrant, leverage, utilize, facilitate. Replace with the plain word.
3. slop constructions: "not just X, but Y"; forced groups of three; fancy "is" ("serves
   as", "stands as", "boasts"); false ranges ("from X to Y" with no scale); superficial
   "-ing" tails ("..., highlighting the importance of ..."); vague attributions ("experts
   say"); generic conclusions ("the future looks bright").
4. slop formatting: em dashes as connectors (use a period or comma), colons as mid-sentence
   glue, bold on every noun, inline-header bullets whose label restates the line, title
   case headings, decorative emoji, curly quotes.
5. hedging: "could potentially possibly" stacks; "may" or the fact, not both.
6. chatbot residue: "I hope this helps", "let me know", "great question", sycophancy.
7. over-compression: dropped articles, verbless fragments, arrow symbol-speak the reader
   must decode. Tight is not terse.
8. mannered prose: aphorisms, personified code, figurative verbs, stock phrases
   ("at the end of the day"). Say the literal thing.

## B. Sentences and structure (technical-writing)

9. clarity: one thought per sentence; split instructions over about 20 words and other
   sentences over about 25; condition before instruction; active voice with the actor
   named; "only" and "not" next to the word they change; every "it", "this", "they"
   points at one obvious noun; no "(s)" plurals, no "and/or", no slashes for "or".
10. clarity: one name per thing throughout the document. Three names for one gate teaches
    three gates.
11. structure: headings carry the point, not just the topic; sentence case; one h1; no
    skipped levels; numbered lists only for sequences; introduce a list with a sentence;
    keep list items parallel.
12. structure: one document, one mode (tutorial, how-to, reference, explanation). Flag
    reference tables inside a tutorial or teaching inside a how-to; propose the split, do
    not perform it.
13. clarity: the real symbol, flag, path or command name in code font, never a description
    of it. Links say where they go, never "click here".
14. duplicate: the same point made twice in different words, or a summary that repeats
    the body. Keep the stronger instance; if both carry a distinct fact, keep both.

## C. Reader load (minimize-reader-load, for documents)

15. structure: count how many hops a reader needs between a question and its answer.
    A section that only forwards to another section is a pass-through layer: propose
    inlining it.
16. structure: state the invariant or rule once, at the boundary (the heading or first
    line of the section), not in every bullet under it.
17. duplicate: a glossary, summary box or "key takeaways" list that restates the body
    adds load without compression unless it is the lookup entry point.

## factual-risk (flag only, never apply)

A statement that looks wrong, outdated, or contradicts another line in the document.
Report it with the two lines that disagree. Never change it.

## Output contract

JSON lines only, at most 8, or `{"findings":0}`:

```
{"id":1,"kind":"filler","lines":"41-43","title":"three hedges stacked on the Docker layer claim","fix":"Replace 'could potentially possibly be slower' with 'is slower'. Keep the layer count and the 2.1 GB figure.","confidence":"high","case":"line 42 stacks could/potentially/possibly","loc_delta":-1}
```

`kind`: filler, slop, duplicate, structure, clarity or factual-risk. `fix`: the exact
replacement (3 short sentences at most) and the facts it keeps. `confidence`: high or
medium. `loc_delta`: estimated net line change.
