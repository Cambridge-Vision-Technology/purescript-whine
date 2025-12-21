-- | Tests for NoStringComparison rule
-- |
-- | Detects string literal comparisons in case statements and guards,
-- | which often indicate that an ADT should be used instead.
module Test.Core.NoStringComparison where

import Test.Prelude

import JSON as JSON
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Whine.Core.NoStringComparison as NoStringComparison
import Whine.Test (runRule)

spec :: Spec Unit
spec = describe "NoStringComparison" do

  describe "case expressions with string patterns" do

    it "Reports string literal in case pattern" $
      hasViolations ["1:2-1:11"] """
        x = case status of
          "pending" -> handlePending
          _ -> handleOther
      """

    it "Reports multiple string literals in case branches" $
      hasViolations ["1:2-1:11", "2:2-2:13", "3:2-3:10"] """
        x = case status of
          "pending" -> handlePending
          "completed" -> handleCompleted
          "failed" -> handleFailed
          _ -> handleUnknown
      """

    it "Allows constructor patterns in case" $
      hasViolations [] """
        x = case status of
          Pending -> handlePending
          Completed -> handleCompleted
          Failed -> handleFailed
      """

    it "Allows variable patterns in case" $
      hasViolations [] """
        x = case value of
          y -> processValue y
      """

  describe "guards with string equality" do

    it "Reports string equality in guards" $
      hasViolations ["1:4-1:29"] """
        processItem item
          | item.status == "document" = processDocument item
          | otherwise = processOther item
      """

    it "Reports string inequality in guards" $
      hasViolations ["1:4-1:28"] """
        processItem item
          | item.status /= "pending" = processActive item
          | otherwise = processOther item
      """

    it "Allows non-string comparisons in guards" $
      hasViolations [] """
        processItem item
          | item.count > 0 = processPositive item
          | otherwise = processZero item
      """

  describe "if expressions with string equality" do

    it "Reports string equality in if condition" $
      hasViolations ["0:7-0:25"] """
        x = if status == "active"
            then handleActive
            else handleInactive
      """

    it "Reports string inequality in if condition" $
      hasViolations ["0:7-0:26"] """
        x = if status /= "pending"
            then handleNotPending
            else handlePending
      """

    it "Allows non-string comparisons in if condition" $
      hasViolations [] """
        x = if count > 0
            then handlePositive
            else handleZero
      """

  describe "operator expressions with string comparison" do

    it "Reports == with string on right side" $
      hasViolations ["1:2-1:20"] """
        isActive status =
          status == "active"
      """

    it "Reports == with string on left side" $
      hasViolations ["1:2-1:20"] """
        isActive status =
          "active" == status
      """

    it "Reports /= with string" $
      hasViolations ["1:2-1:21"] """
        isNotPending status =
          status /= "pending"
      """

  where
    hasViolations vs mod =
      runRule
        { rule: NoStringComparison.rule JSON.null
        , module: mod
        , assertViolationMessage: (_ `shouldEqual` "String comparison detected. Consider using an ADT for type-safe pattern matching.")
        }
      >>= shouldEqual vs
