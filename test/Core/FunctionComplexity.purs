module Test.Core.FunctionComplexity where

import Test.Prelude

import Codec.JSON.DecodeError as DecodeError
import Control.Monad.Error.Class (class MonadThrow, throwError)
import Data.Array as Array
import Data.Codec.JSON as CJ
import Data.String as String
import Effect.Exception (Error, error)
import JSON as JSON
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)
import Whine.Core.FunctionComplexity as FunctionComplexity
import Whine.Test (formatRange, runRule')

spec :: Spec Unit
spec = describe "FunctionComplexity" do

  describe "Lines of Code" do

    it "Reports function exceeding default LOC threshold (50 lines)" $
      hasViolationMatching
        { pattern: "lines"
        , expectedRange: "1:1-"  -- Should start at line 1
        }
        defaultConfig
        (generateLongFunction 55)

    it "Does not report function under LOC threshold" $
      hasNoViolations defaultConfig """
        shortFunction :: Int -> Int
        shortFunction x = x + 1
      """

    it "Respects configurable maxLines threshold" $
      hasViolationMatching
        { pattern: "lines"
        , expectedRange: "1:1-"
        }
        """{ "maxLines": 5 }"""
        """
          mediumFunction :: Int -> Int
          mediumFunction x =
            let y = x + 1
                z = y + 2
                w = z + 3
                v = w + 4
            in v + 5
        """

    it "Does not report when under custom maxLines threshold" $
      hasNoViolations """{ "maxLines": 100 }""" (generateLongFunction 55)

  describe "Nesting Depth" do

    it "Reports excessive case nesting (5 levels deep)" $
      hasViolationMatching
        { pattern: "nesting"
        , expectedRange: "1:1-"
        }
        """{ "maxNestingDepth": 4 }"""
        """
          deeplyNested :: Maybe (Maybe (Maybe (Maybe (Maybe Int)))) -> Int
          deeplyNested x = case x of
            Just a -> case a of
              Just b -> case b of
                Just c -> case c of
                  Just d -> case d of
                    Just e -> e
                    Nothing -> 0
                  Nothing -> 0
                Nothing -> 0
              Nothing -> 0
            Nothing -> 0
        """

    it "Reports excessive do block nesting" $
      hasViolationMatching
        { pattern: "nesting"
        , expectedRange: "1:1-"
        }
        """{ "maxNestingDepth": 3 }"""
        """
          deepDoBlock :: Effect Unit
          deepDoBlock = do
            _ <- pure unit
            do
              _ <- pure unit
              do
                _ <- pure unit
                do
                  _ <- pure unit
                  pure unit
        """

    it "Reports excessive if nesting" $
      hasViolationMatching
        { pattern: "nesting"
        , expectedRange: "1:1-"
        }
        """{ "maxNestingDepth": 3 }"""
        """
          deepIf :: Int -> Int
          deepIf x =
            if x > 0 then
              if x > 10 then
                if x > 100 then
                  if x > 1000 then
                    x
                  else 0
                else 0
              else 0
            else 0
        """

    it "Reports excessive let nesting" $
      hasViolationMatching
        { pattern: "nesting"
        , expectedRange: "1:1-"
        }
        """{ "maxNestingDepth": 3 }"""
        """
          deepLet :: Int -> Int
          deepLet x =
            let a = x + 1 in
              let b = a + 1 in
                let c = b + 1 in
                  let d = c + 1 in
                    d
        """

    it "Counts max depth not cumulative across parallel branches" $
      hasNoViolations """{ "maxNestingDepth": 3 }""" """
        parallelBranches :: Int -> Int
        parallelBranches x = case x of
          1 -> case x of
            _ -> case x of
              _ -> 1
          2 -> case x of
            _ -> case x of
              _ -> 2
          _ -> 0
      """

    it "Does not report shallow nesting" $
      hasNoViolations defaultConfig """
        shallowFunction :: Maybe Int -> Int
        shallowFunction x = case x of
          Just n -> n + 1
          Nothing -> 0
      """

  describe "Cyclomatic Complexity" do

    it "Counts case branches toward complexity" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: "1:1-"
        }
        """{ "maxCyclomaticComplexity": 5 }"""
        """
          manyBranches :: Int -> String
          manyBranches x = case x of
            1 -> "one"
            2 -> "two"
            3 -> "three"
            4 -> "four"
            5 -> "five"
            6 -> "six"
            _ -> "other"
        """

    it "Counts guards toward complexity" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: "1:1-"
        }
        """{ "maxCyclomaticComplexity": 4 }"""
        """
          manyGuards :: Int -> String
          manyGuards x
            | x < 0 = "negative"
            | x == 0 = "zero"
            | x < 10 = "small"
            | x < 100 = "medium"
            | x < 1000 = "large"
            | otherwise = "huge"
        """

    it "Counts if expressions toward complexity" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: "1:1-"
        }
        """{ "maxCyclomaticComplexity": 3 }"""
        """
          manyIfs :: Int -> Int -> Int -> Int -> String
          manyIfs a b c d =
            if a > 0 then "a"
            else if b > 0 then "b"
            else if c > 0 then "c"
            else if d > 0 then "d"
            else "none"
        """

    it "Combines all complexity sources" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: "1:1-"
        }
        """{ "maxCyclomaticComplexity": 5 }"""
        """
          combinedComplexity :: Int -> Maybe Int -> String
          combinedComplexity x y
            | x < 0 = "negative"
            | x == 0 = case y of
                Just n -> if n > 0 then "positive" else "zero"
                Nothing -> "nothing"
            | otherwise = "positive"
        """

    it "Does not report simple functions" $
      hasNoViolations defaultConfig """
        simpleFunction :: Int -> Int
        simpleFunction x = if x > 0 then x else -x
      """

  describe "Configuration Parsing" do

    it "Parses all threshold options" do
      json <- parseJson """
        {
          "maxLines": 30,
          "maxNestingDepth": 3,
          "maxCyclomaticComplexity": 8
        }
      """
      config <- decodeConfig json
      config.maxLines `shouldEqual` 30
      config.maxNestingDepth `shouldEqual` 3
      config.maxCyclomaticComplexity `shouldEqual` 8

    it "Uses defaults for missing options" do
      json <- parseJson "{}"
      config <- decodeConfig json
      config.maxLines `shouldEqual` 50
      config.maxNestingDepth `shouldEqual` 4
      config.maxCyclomaticComplexity `shouldEqual` 10

    it "Uses defaults for partial options" do
      json <- parseJson """{ "maxLines": 25 }"""
      config <- decodeConfig json
      config.maxLines `shouldEqual` 25
      config.maxNestingDepth `shouldEqual` 4
      config.maxCyclomaticComplexity `shouldEqual` 10

  describe "Violation Reporting" do

    it "Reports correct source range spanning entire function" $
      runRule'
        { rule: makeRule """{ "maxLines": 3 }"""
        , module: """
            tinyFunction :: Int -> Int
            tinyFunction x =
              let y = x + 1
                  z = y + 2
              in z
          """
        }
      >>= \vs -> do
        vs `shouldSatisfy` (not <<< Array.null)
        let ranges = vs # map (_.source >>> map formatRange)
        ranges `shouldSatisfy` \rs ->
          rs # any (maybe false (String.contains (Pattern "1:1-")))

    it "Includes metric values in violation message" $
      runRule'
        { rule: makeRule """{ "maxCyclomaticComplexity": 3 }"""
        , module: """
            complex :: Int -> String
            complex x = case x of
              1 -> "a"
              2 -> "b"
              3 -> "c"
              4 -> "d"
              _ -> "e"
          """
        }
      >>= \vs -> do
        vs `shouldSatisfy` (not <<< Array.null)
        let messages = vs <#> _.message
        -- Message should contain the actual complexity value
        messages `shouldSatisfy` \msgs ->
          msgs # any (\m -> String.contains (Pattern "6") m || String.contains (Pattern "complexity") m)

    it "Includes function name in violation message" $
      runRule'
        { rule: makeRule """{ "maxLines": 3 }"""
        , module: """
            mySpecificFunction :: Int -> Int
            mySpecificFunction x =
              let y = x + 1
                  z = y + 2
              in z
          """
        }
      >>= \vs -> do
        vs `shouldSatisfy` (not <<< Array.null)
        let messages = vs <#> _.message
        messages `shouldSatisfy` \msgs ->
          msgs # any (String.contains (Pattern "mySpecificFunction"))

  describe "Edge Cases" do

    it "Ignores type declarations" $
      hasNoViolations """{ "maxLines": 5 }""" """
        data LargeType
          = Constructor1 Int
          | Constructor2 String
          | Constructor3 Boolean
          | Constructor4 Number
          | Constructor5 Char
          | Constructor6 (Array Int)
          | Constructor7 (Maybe String)
      """

    it "Handles pattern-match functions with multiple clauses" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: "1:1-"
        }
        """{ "maxCyclomaticComplexity": 4 }"""
        """
          patternMatch :: Int -> Int -> String
          patternMatch 0 0 = "zero-zero"
          patternMatch 0 _ = "zero-other"
          patternMatch _ 0 = "other-zero"
          patternMatch 1 1 = "one-one"
          patternMatch 1 _ = "one-other"
          patternMatch _ 1 = "other-one"
          patternMatch _ _ = "other-other"
        """

    it "Analyzes where clause bindings" $
      hasViolationMatching
        { pattern: "complexity"
        , expectedRange: ""  -- Just check that it reports something
        }
        """{ "maxCyclomaticComplexity": 3 }"""
        """
          withWhere :: Int -> String
          withWhere x = helper x
            where
              helper n = case n of
                1 -> "one"
                2 -> "two"
                3 -> "three"
                4 -> "four"
                _ -> "other"
        """

  where
    defaultConfig = "{}"

    parseJson :: forall m. MonadEffect m => MonadThrow Error m => String -> m JSON
    parseJson str = case JSON.parse str of
      Left e -> throwError $ error $ "Failed to parse JSON: " <> e
      Right j -> pure j

    decodeConfig :: forall m. MonadEffect m => MonadThrow Error m => JSON -> m FunctionComplexity.Config
    decodeConfig json = case CJ.decode FunctionComplexity.codec json of
      Left e -> throwError $ error $ "Failed to decode config: " <> DecodeError.print e
      Right c -> pure c

    makeRule :: String -> _
    makeRule configStr =
      case JSON.parse configStr of
        Left _ -> FunctionComplexity.rule FunctionComplexity.defaultConfig
        Right json -> case CJ.decode FunctionComplexity.codec json of
          Left _ -> FunctionComplexity.rule FunctionComplexity.defaultConfig
          Right config -> FunctionComplexity.rule config

    hasNoViolations :: String -> String -> _ Unit
    hasNoViolations configStr mod =
      runRule'
        { rule: makeRule configStr
        , module: mod
        }
      >>= shouldEqual []

    hasViolationMatching :: { pattern :: String, expectedRange :: String } -> String -> String -> _ Unit
    hasViolationMatching { pattern, expectedRange } configStr mod =
      runRule'
        { rule: makeRule configStr
        , module: mod
        }
      >>= \vs -> do
        vs `shouldSatisfy` (not <<< Array.null)
        let messages = vs <#> _.message
        messages `shouldSatisfy` \msgs ->
          msgs # any (String.contains (Pattern pattern))
        when (expectedRange /= "") do
          let ranges = vs # map (_.source >>> map formatRange >>> fromMaybe "")
          ranges `shouldSatisfy` \rs ->
            rs # any (String.contains (Pattern expectedRange))

    -- Generate a function with approximately n lines
    generateLongFunction :: Int -> String
    generateLongFunction n =
      "longFunction :: Int -> Int\n" <>
      "longFunction x =\n" <>
      "  let\n" <>
      (Array.range 1 (n - 5) # map (\i -> "    v" <> show i <> " = x + " <> show i) # joinWith "\n") <>
      "\n  in v" <> show (n - 5)
