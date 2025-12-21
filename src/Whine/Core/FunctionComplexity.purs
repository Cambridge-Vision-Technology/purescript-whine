-- | Detects large, complex functions that may need refactoring.
-- |
-- | This rule analyzes function declarations and reports violations when:
-- | - Function exceeds a configurable lines of code threshold
-- | - Function has excessive nesting depth (case/do/if/let expressions)
-- | - Function has high cyclomatic complexity (branches + guards + ifs)
-- |
-- | Configuration example:
-- |     FunctionComplexity:
-- |       maxLines: 50
-- |       maxNestingDepth: 4
-- |       maxCyclomaticComplexity: 10
-- |
module Whine.Core.FunctionComplexity
  ( rule
  , codec
  , defaultConfig
  , Config
  )
  where

import Whine.Prelude

import Data.Foldable (sum)

import Data.Array.NonEmpty as NEA
import Data.Codec.JSON as CJ
import Data.Codec.JSON.Record as CJR
import PureScript.CST.Range (class RangeOf, rangeOf)
import PureScript.CST.Types (AppSpine(..), Declaration(..), DoStatement(..), Expr(..), Guarded(..), GuardedExpr(..), Ident, LetBinding(..), Name(..), PatternGuard(..), RecordLabeled(..), Separated(..), Token(..), ValueBindingFields, Where(..), Wrapped(..))
import Whine.Types (class MonadRules, Handle(..), Rule, emptyRule, reportViolation)

type Config =
  { maxLines :: Int
  , maxNestingDepth :: Int
  , maxCyclomaticComplexity :: Int
  }

type RawConfig =
  { maxLines :: Maybe Int
  , maxNestingDepth :: Maybe Int
  , maxCyclomaticComplexity :: Maybe Int
  }

defaultConfig :: Config
defaultConfig =
  { maxLines: 50
  , maxNestingDepth: 4
  , maxCyclomaticComplexity: 10
  }

rawToConfig :: RawConfig -> Config
rawToConfig raw =
  { maxLines: fromMaybe defaultConfig.maxLines raw.maxLines
  , maxNestingDepth: fromMaybe defaultConfig.maxNestingDepth raw.maxNestingDepth
  , maxCyclomaticComplexity: fromMaybe defaultConfig.maxCyclomaticComplexity raw.maxCyclomaticComplexity
  }

codec :: CJ.Codec Config
codec = dimap configToRaw rawToConfig rawCodec
  where
    configToRaw :: Config -> RawConfig
    configToRaw c =
      { maxLines: Just c.maxLines
      , maxNestingDepth: Just c.maxNestingDepth
      , maxCyclomaticComplexity: Just c.maxCyclomaticComplexity
      }

    rawCodec :: CJ.Codec RawConfig
    rawCodec = CJR.object
      { maxLines: CJR.optional CJ.int
      , maxNestingDepth: CJR.optional CJ.int
      , maxCyclomaticComplexity: CJR.optional CJ.int
      }

rule :: Config -> Rule
rule config = emptyRule { onDecl = onDecl }
  where
    onDecl :: Handle Declaration
    onDecl = Handle case _ of
      DeclValue valueBinding -> analyzeFunction config valueBinding
      _ -> pure unit

analyzeFunction
  :: forall e m
   . MonadRules () m
  => RangeOf e
  => Config
  -> ValueBindingFields e
  -> m Unit
analyzeFunction config binding = do
  let
    functionName = getFunctionName binding.name
    nameRange = rangeOf binding.name
    guardedRange = rangeOf binding.guarded
    sourceRange = unionRanges nameRange guardedRange

    linesOfCode = sourceRange.end.line - sourceRange.start.line + 1
    nestingDepth = calculateNestingDepth binding.guarded
    cyclomaticComplexity = calculateCyclomaticComplexity binding

    violations = fold
      [ if linesOfCode > config.maxLines
          then [ "lines of code: " <> show linesOfCode <> " (max " <> show config.maxLines <> ")" ]
          else []
      , if nestingDepth > config.maxNestingDepth
          then [ "nesting depth: " <> show nestingDepth <> " (max " <> show config.maxNestingDepth <> ")" ]
          else []
      , if cyclomaticComplexity > config.maxCyclomaticComplexity
          then [ "cyclomatic complexity: " <> show cyclomaticComplexity <> " (max " <> show config.maxCyclomaticComplexity <> ")" ]
          else []
      ]

  unless (null violations) $
    reportViolation
      { source: Just sourceRange
      , message: "Function '" <> functionName <> "' exceeds complexity thresholds: " <> joinWith ", " violations
      }

getFunctionName :: Name Ident -> String
getFunctionName (Name { token }) = case token.value of
  TokLowerName _ name -> name
  _ -> "<unknown>"

-- | Calculate maximum nesting depth of case/do/if/let expressions
calculateNestingDepth :: forall e. Guarded e -> Int
calculateNestingDepth guarded = case guarded of
  Unconditional _ whereClause -> whereNestingDepth 0 whereClause
  Guarded guardedExprs ->
    NEA.toArray guardedExprs
      # map (\(GuardedExpr g) -> whereNestingDepth 0 g.where)
      # maximum
      # fromMaybe 0

whereNestingDepth :: forall e. Int -> Where e -> Int
whereNestingDepth depth (Where { expr, bindings }) =
  max
    (exprNestingDepth depth expr)
    (bindings # maybe depth (\(_ /\ bs) ->
      NEA.toArray bs
        # map (letBindingNestingDepth depth)
        # maximum
        # fromMaybe depth
    ))

letBindingNestingDepth :: forall e. Int -> LetBinding e -> Int
letBindingNestingDepth depth = case _ of
  LetBindingName vb -> guardedNestingDepth depth vb.guarded
  LetBindingPattern _ _ w -> whereNestingDepth depth w
  _ -> depth

guardedNestingDepth :: forall e. Int -> Guarded e -> Int
guardedNestingDepth depth guarded = case guarded of
  Unconditional _ w -> max depth (whereNestingDepth depth w)
  Guarded gs ->
    NEA.toArray gs
      # map (\(GuardedExpr g) -> whereNestingDepth depth g.where)
      # maximum
      # fromMaybe depth
      # max depth

exprNestingDepth :: forall e. Int -> Expr e -> Int
exprNestingDepth depth = case _ of
  ExprCase caseOf ->
    let newDepth = depth + 1
        branchDepths = NEA.toArray caseOf.branches # map \(_ /\ guarded) ->
          guardedNestingDepth newDepth guarded
    in maximum branchDepths # fromMaybe newDepth

  ExprIf ifThenElse ->
    let newDepth = depth + 1
    in max
        (exprNestingDepth newDepth ifThenElse.true)
        (exprNestingDepth newDepth ifThenElse.false)

  ExprLet letIn ->
    let newDepth = depth + 1
        bindingDepths = NEA.toArray letIn.bindings # map (letBindingNestingDepth newDepth)
        bodyDepth = exprNestingDepth newDepth letIn.body
    in max bodyDepth (maximum bindingDepths # fromMaybe newDepth)

  ExprDo doBlock ->
    let newDepth = depth + 1
        statementDepths = NEA.toArray doBlock.statements # map (doStatementNestingDepth newDepth)
    in maximum statementDepths # fromMaybe newDepth

  ExprLambda lambda ->
    exprNestingDepth depth lambda.body

  ExprApp expr args ->
    let exprDepth = exprNestingDepth depth expr
        argDepths = NEA.toArray args # mapMaybe case _ of
          AppTerm e -> Just (exprNestingDepth depth e)
          _ -> Nothing
    in maximum (exprDepth : argDepths) # fromMaybe depth

  ExprParens (Wrapped { value }) ->
    exprNestingDepth depth value

  ExprTyped expr _ _ ->
    exprNestingDepth depth expr

  ExprOp expr ops ->
    let exprDepth = exprNestingDepth depth expr
        opDepths = NEA.toArray ops # map (\(_ /\ e) -> exprNestingDepth depth e)
    in maximum (exprDepth : opDepths) # fromMaybe depth

  ExprNegate _ expr ->
    exprNestingDepth depth expr

  ExprArray (Wrapped { value }) ->
    value
      # maybe depth (separatedMaxDepth depth)

  ExprRecord (Wrapped { value }) ->
    value
      # maybe depth (separatedRecordMaxDepth depth)

  _ -> depth

separatedMaxDepth :: forall e. Int -> Separated (Expr e) -> Int
separatedMaxDepth d (Separated { head, tail }) =
  let depths = exprNestingDepth d head : (tail # map (\(_ /\ e) -> exprNestingDepth d e))
  in maximum depths # fromMaybe d

separatedRecordMaxDepth :: forall e. Int -> Separated (RecordLabeled (Expr e)) -> Int
separatedRecordMaxDepth d (Separated { head, tail }) =
  let getExprDepth = case _ of
        RecordPun _ -> d
        RecordField _ _ e -> exprNestingDepth d e
      depths = getExprDepth head : (tail # map (\(_ /\ r) -> getExprDepth r))
  in maximum depths # fromMaybe d

doStatementNestingDepth :: forall e. Int -> DoStatement e -> Int
doStatementNestingDepth depth = case _ of
  DoLet _ bindings ->
    NEA.toArray bindings
      # map (letBindingNestingDepth depth)
      # maximum
      # fromMaybe depth
  DoDiscard expr -> exprNestingDepth depth expr
  DoBind _ _ expr -> exprNestingDepth depth expr
  _ -> depth

-- | Calculate cyclomatic complexity
-- | Counts: case branches + guards + if expressions + 1
calculateCyclomaticComplexity :: forall e. ValueBindingFields e -> Int
calculateCyclomaticComplexity binding =
  1 + binderComplexity + guardedComplexity binding.guarded
  where
    binderComplexity = length binding.binders

guardedComplexity :: forall e. Guarded e -> Int
guardedComplexity = case _ of
  Unconditional _ whereClause -> whereComplexity whereClause
  Guarded guardedExprs ->
    let guardCount = NEA.length guardedExprs
        exprComplexity' = NEA.toArray guardedExprs
          # map (\(GuardedExpr g) ->
              patternGuardComplexity g.patterns + whereComplexity g.where
            )
          # sum
    in guardCount + exprComplexity'

patternGuardComplexity :: forall e. Separated (PatternGuard e) -> Int
patternGuardComplexity (Separated { head, tail }) =
  patternGuardExprComplexity head + (tail # map (snd >>> patternGuardExprComplexity) # sum)
  where
    patternGuardExprComplexity :: PatternGuard e -> Int
    patternGuardExprComplexity (PatternGuard { expr }) = exprComplexity expr

whereComplexity :: forall e. Where e -> Int
whereComplexity (Where { expr, bindings }) =
  exprComplexity expr +
    (bindings # maybe 0 (\(_ /\ bs) ->
      NEA.toArray bs # map letBindingComplexity # sum
    ))

letBindingComplexity :: forall e. LetBinding e -> Int
letBindingComplexity = case _ of
  LetBindingName vb -> guardedComplexity vb.guarded
  LetBindingPattern _ _ w -> whereComplexity w
  _ -> 0

exprComplexity :: forall e. Expr e -> Int
exprComplexity = case _ of
  ExprCase caseOf ->
    let branchCount = NEA.length caseOf.branches
        branchComplexity = NEA.toArray caseOf.branches
          # map (\(_ /\ guarded) -> guardedComplexity guarded)
          # sum
        headComplexity = separatedExprComplexity caseOf.head
    in branchCount + branchComplexity + headComplexity

  ExprIf ifThenElse ->
    1 + exprComplexity ifThenElse.cond
      + exprComplexity ifThenElse.true
      + exprComplexity ifThenElse.false

  ExprLet letIn ->
    let bindingComplexity = NEA.toArray letIn.bindings # map letBindingComplexity # sum
    in bindingComplexity + exprComplexity letIn.body

  ExprDo doBlock ->
    NEA.toArray doBlock.statements # map doStatementComplexity # sum

  ExprLambda lambda ->
    exprComplexity lambda.body

  ExprApp expr args ->
    exprComplexity expr + (NEA.toArray args # mapMaybe appSpineExprComplexity # sum)

  ExprParens (Wrapped { value }) ->
    exprComplexity value

  ExprTyped expr _ _ ->
    exprComplexity expr

  ExprOp expr ops ->
    exprComplexity expr + (NEA.toArray ops # map (\(_ /\ e) -> exprComplexity e) # sum)

  ExprNegate _ expr ->
    exprComplexity expr

  ExprArray (Wrapped { value }) ->
    value # maybe 0 separatedExprComplexity

  ExprRecord (Wrapped { value }) ->
    value # maybe 0 separatedRecordComplexity

  ExprAdo adoBlock ->
    (adoBlock.statements # map doStatementComplexity # sum) + exprComplexity adoBlock.result

  _ -> 0

appSpineExprComplexity :: forall e. AppSpine Expr e -> Maybe Int
appSpineExprComplexity = case _ of
  AppTerm e -> Just (exprComplexity e)
  _ -> Nothing

separatedExprComplexity :: forall e. Separated (Expr e) -> Int
separatedExprComplexity (Separated { head, tail }) =
  exprComplexity head + (tail # map (\(_ /\ e) -> exprComplexity e) # sum)

separatedRecordComplexity :: forall e. Separated (RecordLabeled (Expr e)) -> Int
separatedRecordComplexity (Separated { head, tail }) =
  let getComplexity = case _ of
        RecordPun _ -> 0
        RecordField _ _ e -> exprComplexity e
  in getComplexity head + (tail # map (\(_ /\ r) -> getComplexity r) # sum)

doStatementComplexity :: forall e. DoStatement e -> Int
doStatementComplexity = case _ of
  DoLet _ bindings -> NEA.toArray bindings # map letBindingComplexity # sum
  DoDiscard expr -> exprComplexity expr
  DoBind _ _ expr -> exprComplexity expr
  _ -> 0
