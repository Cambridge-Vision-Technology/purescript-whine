-- | Detects string comparisons on record fields, which often indicate
-- | that the field should be an ADT instead of a String.
-- |
-- | This rule specifically targets:
-- |     record.field == "value"  -- field should be an ADT!
-- |     record.field /= "value"
-- |
-- | It does NOT flag boundary parsing patterns like:
-- |     case externalString of
-- |       "pending" -> Just Pending  -- legitimate parsing
-- |
-- | The distinction is:
-- | - Record field access suggests internal data that should be typed
-- | - Case patterns on variables suggest parsing external strings
-- |
module Whine.Core.NoStringComparison where

import Whine.Prelude

import Data.Array.NonEmpty as NEA
import PureScript.CST.Range (rangeOf)
import PureScript.CST.Types (Expr(..), Operator(..), RecordAccessor(..), Wrapped(..))
import Whine.Types (Handle(..), Rule, emptyRule, reportViolation)

rule :: JSON -> Rule
rule _ = emptyRule
  { onExpr = onExpr
  }
  where
    violationMessage :: String
    violationMessage = "String comparison on record field detected. Consider using an ADT for type-safe pattern matching."

    onExpr :: Handle Expr
    onExpr = Handle case _ of
      ExprOp leftExpr ops ->
        for_ (NEA.toArray ops) \(qualifiedOp /\ rightExpr) ->
          let
            Operator opName = (unwrap qualifiedOp).name
          in
            when (opName == "==" || opName == "/=") $
              when (isRecordFieldStringComparison leftExpr rightExpr) $
                reportViolation
                  { source: unionManyRanges [rangeOf leftExpr, rangeOf rightExpr]
                  , message: violationMessage
                  }
      _ -> pure unit

    -- Check if this is record.field == "string" or "string" == record.field
    isRecordFieldStringComparison :: forall e. Expr e -> Expr e -> Boolean
    isRecordFieldStringComparison left right =
      (isRecordAccessor left && isStringExpr right)
        || (isStringExpr left && isRecordAccessor right)

    isRecordAccessor :: forall e. Expr e -> Boolean
    isRecordAccessor = case _ of
      ExprRecordAccessor _ -> true
      ExprParens (Wrapped { value }) -> isRecordAccessor value
      _ -> false

    isStringExpr :: forall e. Expr e -> Boolean
    isStringExpr = case _ of
      ExprString _ _ -> true
      ExprParens (Wrapped { value }) -> isStringExpr value
      _ -> false
