-- | Tests for NoStringComparison rule
-- |
-- | This rule detects string comparisons on record fields,
-- | which often indicate the field should be an ADT.
module Test.Core.NoStringComparison where

import Test.Prelude

import JSON as JSON
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)
import Whine.Core.NoStringComparison as NoStringComparison
import Whine.Test (runRule)

spec :: Spec Unit
spec = describe "NoStringComparison" do

  describe "record field comparisons (should flag)" do

    it "Reports record.field == string" $
      hasViolations ["1:2-1:26"] """
        check item =
          item.status == "pending"
      """

    it "Reports string == record.field" $
      hasViolations ["1:2-1:26"] """
        check item =
          "pending" == item.status
      """

    it "Reports record.field /= string" $
      hasViolations ["1:2-1:26"] """
        check item =
          item.status /= "pending"
      """

    it "Reports nested record access" $
      hasViolations ["1:2-1:31"] """
        check item =
          item.data.fieldType == "text"
      """

  describe "case expressions (should NOT flag - boundary parsing)" do

    it "Allows string patterns in case" $
      hasViolations [] """
        parseStatus str = case str of
          "pending" -> Just Pending
          "complete" -> Just Complete
          _ -> Nothing
      """

    it "Allows string patterns matching external data" $
      hasViolations [] """
        decodeLevel level = case level of
          "trace" -> Trace
          "debug" -> Debug
          "info" -> Info
          _ -> Info
      """

  describe "variable comparisons (should NOT flag)" do

    it "Allows variable == string" $
      hasViolations [] """
        checkEmpty str =
          str == ""
      """

    it "Allows function result == string" $
      hasViolations [] """
        checkExt path =
          getExtension path == ".pdf"
      """

  describe "guards with record fields (should flag)" do

    it "Reports record field in guard" $
      hasViolations ["1:4-1:29"] """
        processItem item
          | item.status == "document" = processDocument item
          | otherwise = processOther item
      """

  where
    hasViolations vs mod =
      runRule
        { rule: NoStringComparison.rule JSON.null
        , module: mod
        , assertViolationMessage: (_ `shouldEqual` "String comparison on record field detected. Consider using an ADT for type-safe pattern matching.")
        }
      >>= shouldEqual vs
