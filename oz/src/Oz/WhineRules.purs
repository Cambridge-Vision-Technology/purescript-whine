-- | Oz project-specific whine rules
-- | These rules apply only to the Oz project
module Oz.WhineRules where

import Whine.Core.UndesirableFunctions as UF
import Whine.Types (RuleFactories, ruleFactory)

-- | Export all rules for this package
rules :: RuleFactories
rules =
  -- Project-specific rules - use capability abstractions instead of direct implementations
  [ ruleFactory "UndesirableNdjson" UF.codec UF.rule    -- Logger.Ndjson.* functions
  , ruleFactory "UndesirableViewSend" UF.codec UF.rule  -- View.Send.* functions
  ]
