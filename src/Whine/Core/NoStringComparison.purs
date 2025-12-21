-- | Detects string literal comparisons in case statements and guards,
-- | which often indicate that an ADT (Algebraic Data Type) should be used instead.
-- |
-- | String comparisons in pattern matching are a code smell:
-- |     -- Anti-pattern:
-- |     case status of
-- |       "pending" -> handlePending
-- |       "completed" -> handleCompleted
-- |       _ -> handleUnknown
-- |
-- |     -- Also problematic:
-- |     if status == "active" then ...
-- |     | item.type == "document" = ...
-- |
-- |     -- Preferred:
-- |     data Status = Pending | Completed | Failed
-- |     case status of
-- |       Pending -> handlePending
-- |       Completed -> handleCompleted
-- |       Failed -> handleFailed
-- |
module Whine.Core.NoStringComparison where

import Whine.Prelude

import Data.Array.NonEmpty as NEA
import PureScript.CST.Range (rangeOf)
import PureScript.CST.Types (Binder(..), Expr(..), Operator(..), Wrapped(..))
import Whine.Types (Handle(..), Rule, emptyRule, reportViolation)

rule :: JSON -> Rule
rule _ = emptyRule
  { onBinder = onBinder
  , onExpr = onExpr
  }
  where
    violationMessage :: String
    violationMessage = "String comparison detected. Consider using an ADT for type-safe pattern matching."

    onBinder :: Handle Binder
    onBinder = Handle case _ of
      BinderString token _ ->
        reportViolation
          { source: Just token.range
          , message: violationMessage
          }
      _ -> pure unit

    onExpr :: Handle Expr
    onExpr = Handle case _ of
      ExprOp leftExpr ops ->
        for_ (NEA.toArray ops) \(qualifiedOp /\ rightExpr) ->
          let
            Operator opName = (unwrap qualifiedOp).name
          in
            when (opName == "==" || opName == "/=") $
              when (isStringExpr leftExpr || isStringExpr rightExpr) $
                reportViolation
                  { source: unionManyRanges [rangeOf leftExpr, rangeOf rightExpr]
                  , message: violationMessage
                  }
      _ -> pure unit

    isStringExpr :: forall e. Expr e -> Boolean
    isStringExpr = case _ of
      ExprString _ _ -> true
      ExprParens (Wrapped { value }) -> isStringExpr value
      _ -> false
