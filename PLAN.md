# Issue #2: EtaReduce Rule

**Rule name**: `EtaReduce`
**Issue**: https://github.com/collegevine/purescript-whine/issues/2
**Summary**: Detect function bindings where the last parameter is redundantly applied and could be eta-reduced to point-free style.

## Task 1: Write BDD Integration Tests (Red Phase)

- [ ] Create integration test fixtures that run the actual `whine` CLI against PureScript source files
- [ ] Verify tests fail because the rule doesn't exist yet

### Scenarios that SHOULD be flagged

| # | Input | Expected suggestion |
|---|-------|-------------------|
| 1 | `f a = g a` | Could be `f = g` |
| 2 | `f a = h $ g a` | Could be point-free |
| 3 | `f a = j $ h $ g a` | Could be point-free |
| 4 | `f a b = g a b` | Last param `b` is redundant |

### Scenarios that should NOT be flagged

| # | Input | Reason |
|---|-------|--------|
| 5 | `f = g` | Already point-free |
| 6 | `f a = g b` | Different variable |
| 7 | `f a = g (h a)` | `a` is nested, not direct last arg |
| 8 | Guarded: `f a \| c = g a \| otherwise = h a` | Can't eta-reduce guarded bindings |
| 9 | Type class instance method: `instance Foo Bar where foo a = bar a` | Excluded per issue discussion |
| 10 | `f a = a + 1` | `a` is not the last argument of a function application |
| 11 | `f _ = g unit` | Wildcard binder, not a named variable match |

## Task 2: Implement the `EtaReduce` Rule

- [ ] Create `src/Whine/Core/EtaReduce.purs`
- [ ] Use `onDecl` handler matching `DeclValue` bindings
- [ ] Check that the last binder is a simple `BinderVar`
- [ ] Check that the binding is `Unconditional` (no guards)
- [ ] Check that the body expression's last applied argument is `ExprIdent` matching the last binder's name
- [ ] Handle two forms:
  - **Direct application** (`ExprApp`): `g a` where `a` matches last binder
  - **Dollar-chain** (`ExprOp` with `$`): `h $ g a` where rightmost expression ends with last binder
- [ ] Skip type class instance methods
- [ ] No configuration needed initially (use `CJ.json` / raw JSON codec)

## Task 3: Register the Rule & Add Unit Tests

- [ ] Register `EtaReduce` in `src/Whine/Core/WhineRules.purs`
- [ ] Add unit tests in `test/Core/EtaReduce.purs` using `runRule`/`runRule'`
- [ ] Register test spec in `test/Core/WhineRules.purs`
- [ ] Add rule to `whine.yaml` config

## Task 4: Rebuild Bundle & Verify

- [ ] Rebuild the whine-core bundle (`dist/bundle.sh`)
- [ ] Run `nix flake check` to verify all tests pass (unit + integration)
- [ ] Verify integration tests now pass (green phase)
