module Whine.Core.WhineRules
  ( rules
  )
  where

import Whine.Core.CaseBranchIndentation as CaseBranchIndentation
import Whine.Core.CommaFirstArrays as CommaFirstArrays
import Whine.Core.CommaFirstRecords as CommaFirstRecords
import Whine.Core.FunctionComplexity as FunctionComplexity
import Whine.Core.UndesirableFunctions as UndesirableFunctions
import Whine.Core.UndesirableModules as UndesirableModules
import Whine.Types (RuleFactories, ruleFactory)
import Data.Codec.JSON as CJ

rules :: RuleFactories
rules =
  [ ruleFactory "UndesirableModules" UndesirableModules.codec UndesirableModules.rule
  , ruleFactory "UndesirableFunctions" UndesirableFunctions.codec UndesirableFunctions.rule
  , ruleFactory "CommaFirstArrays" CJ.json CommaFirstArrays.rule
  , ruleFactory "CommaFirstRecords" CJ.json CommaFirstRecords.rule
  , ruleFactory "CaseBranchIndentation" CJ.json CaseBranchIndentation.rule
  , ruleFactory "FunctionComplexity" FunctionComplexity.codec FunctionComplexity.rule
  ]
