# Prior knowledge: deep-module concept and house vocabulary

The user has been designing this app with deep modules deliberately and knows the concept
(Ousterhout-style, via the repo's `codebase-design` skill). Do not teach what a deep module
is; teach the *specific interfaces of this codebase* and the relationships between them.
Lessons should assume the glossary terms (module, interface, seam, adapter, depth, leverage,
locality) and spend their working-memory budget on this repo's contracts instead.

## Implications
- Zone of proximal development starts at "name the modules and their contracts", not at
  "what is an interface".
- Quizzes should pose architectural decisions ("where does this feature go?"), not
  definitional recall.
- Explicitly out of bounds: implementation walkthroughs ("under the iceberg").
