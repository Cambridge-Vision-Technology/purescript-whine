module PSExtract.WhineRules where

import Whine.Prelude

import Data.Array.NonEmpty as Data.Array.NonEmpty
import Data.Codec.JSON as CJ
import Data.Foldable (all) as Data.Foldable
import PureScript.CST.Types (Import(..), ImportDecl(..), Module(..), ModuleHeader(..), ModuleName(..), Name(..), Separated(..), Wrapped(..))
import Whine.Types (Handle(..), Rule, RuleFactories, emptyRule, reportViolation, ruleFactory)

-- | Export all rules for this package
rules :: RuleFactories
rules =
  [ ruleFactory "QualifiedImportsOnly" CJ.json qualifiedImportsOnlyRule
  , ruleFactory "MatchingAliases" CJ.json matchingAliasesRule
  , ruleFactory "NoDuplicateImports" CJ.json noDuplicateImportsRule
  ]

-- | Rule: All imports must be qualified (except Prelude and symbol-only imports)
-- | Enforces: import Data.Maybe as Data.Maybe
-- | Rejects: import Data.Maybe
-- | Allows: import Prelude, import Type.Row (type (+)), import Data.Argonaut.Decode.Class (class DecodeJson)
qualifiedImportsOnlyRule :: JSON -> Rule
qualifiedImportsOnlyRule _ = emptyRule { onModuleImport = onImport }
  where
  onImport = Handle case _ of
    ImportDecl { module: Name m, qualified, names } ->
      case qualified, m.name, names of
        -- Allow: import Prelude (no qualification needed)
        Nothing, ModuleName "Prelude", _ -> pure unit

        -- Allow: symbol-only imports like import Type.Row (type (+)), import Data.Argonaut.Decode.Class (class DecodeJson)
        Nothing, _, Just (_ /\ imports) | isSymbolOnlyImport imports -> pure unit

        -- Reject: mixed imports (regular items + operators/classes)
        Nothing, _, Just (_ /\ imports) | isMixedImport imports ->
          reportViolation
            { source: Just m.token.range
            , message: "Mixed import contains both regular items and operators/classes. Split into two imports:\n"
                <> "  (1) import "
                <> unwrap m.name
                <> " as "
                <> unwrap m.name
                <> "  -- for types/functions\n"
                <> "  (2) import "
                <> unwrap m.name
                <> " (<operators/classes>)  -- for operators and type classes only"
            }

        -- Reject: bare imports without qualification
        Nothing, _, _ ->
          reportViolation
            { source: Just m.token.range
            , message: "Import must be qualified with 'as " <> unwrap m.name <> "'. Use: import " <> unwrap m.name <> " as " <> unwrap m.name
            }

        -- Allow: qualified imports (checked by MatchingAliases rule)
        Just _, _, _ -> pure unit

  -- Check if import list contains only symbols (operators, type operators, and type classes)
  isSymbolOnlyImport :: forall e. Wrapped (Separated (Import e)) -> Boolean
  isSymbolOnlyImport (Wrapped { value: Separated { head, tail } }) =
    isSymbol head && Data.Foldable.all (isSymbol <<< snd) tail

  -- Check if import list is mixed (contains both operators and non-operators)
  isMixedImport :: forall e. Wrapped (Separated (Import e)) -> Boolean
  isMixedImport (Wrapped { value: Separated { head, tail } }) =
    let
      allItems = head : (snd <$> tail)
      hasOperator = any isSymbol allItems
      hasRegular = any (not <<< isSymbol) allItems
    in
      hasOperator && hasRegular

  isSymbol :: forall e. Import e -> Boolean
  isSymbol (ImportTypeOp _ _) = true
  isSymbol (ImportOp _) = true
  isSymbol (ImportClass _ _) = true -- Allow type class imports like (class DecodeJson)
  isSymbol _ = false

-- | Rule: Qualified aliases must match the module name exactly
-- | Enforces: import Data.Maybe as Data.Maybe
-- | Rejects: import Data.Maybe as M, import Data.Maybe as Maybe
matchingAliasesRule :: JSON -> Rule
matchingAliasesRule _ = emptyRule { onModuleImport = onImport }
  where
  onImport = Handle case _ of
    ImportDecl { module: Name m, qualified: Just (_ /\ Name alias) } ->
      if m.name == alias.name then pure unit
      else
        reportViolation
          { source: Just alias.token.range
          , message: "Import alias must match module name. Use: as " <> unwrap m.name <> " (not as " <> unwrap alias.name <> ")"
          }

    -- No qualified alias, rule doesn't apply (handled by QualifiedImportsOnly)
    ImportDecl _ -> pure unit

-- | Rule: No duplicate imports of the same module
-- | Checks all imports in a module and reports duplicates
-- | Exception: Allows symbol-only imports (operators, type classes) to coexist with qualified imports
-- | Valid pattern: import Module as Module + import Module ((operator)) or import Module (class ClassName)
noDuplicateImportsRule :: JSON -> Rule
noDuplicateImportsRule _ = emptyRule { onModule = onModule }
  where
  onModule = Handle case _ of
    Module { header: ModuleHeader { imports } } -> do
      let
        -- Group imports by module name
        grouped = groupAllBy compareModuleName imports

        -- Find groups with more than one import (length > 1)
        duplicates = filter (\g -> Data.Array.NonEmpty.length g > 1) grouped

      -- Report each duplicate group
      for_ duplicates \group ->
        let
          { head: ImportDecl { module: Name m }, tail } = Data.Array.NonEmpty.uncons group
          -- Filter out symbol-only imports (operators/classes) from duplicates (they're allowed)
          nonSymbolDuplicates = filter (not <<< isSymbolOnlyImportDecl) tail
        in
          for_ nonSymbolDuplicates \(ImportDecl { module: Name dup }) ->
            reportViolation
              { source: Just dup.token.range
              , message: "Duplicate import of module '" <> unwrap m.name <> "'. Remove duplicate imports."
              }

  compareModuleName :: forall e. ImportDecl e -> ImportDecl e -> Ordering
  compareModuleName (ImportDecl { module: Name m1 }) (ImportDecl { module: Name m2 }) =
    compare m1.name m2.name

  -- Check if an import declaration is symbol-only (operators/classes)
  isSymbolOnlyImportDecl :: forall e. ImportDecl e -> Boolean
  isSymbolOnlyImportDecl (ImportDecl { names: Just (_ /\ imports) }) = isSymbolOnlyImport imports
  isSymbolOnlyImportDecl _ = false

  -- Check if import list contains only symbols (operators, type operators, and type classes)
  isSymbolOnlyImport :: forall e. Wrapped (Separated (Import e)) -> Boolean
  isSymbolOnlyImport (Wrapped { value: Separated { head, tail } }) =
    isSymbol head && Data.Foldable.all (isSymbol <<< snd) tail

  isSymbol :: forall e. Import e -> Boolean
  isSymbol (ImportTypeOp _ _) = true
  isSymbol (ImportOp _) = true
  isSymbol (ImportClass _ _) = true -- Allow type class imports like (class DecodeJson)
  isSymbol _ = false
