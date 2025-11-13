module Whine.Bootstrap.WhineCoreMain where

import Whine.Runner.Prelude

import PSExtract.WhineRules as OzRules
import Whine.Core.WhineRules as WhineRules
import Whine.Runner (runWhineAndPrintResultsAndExit)

-- | Entry point for pre-bundled whine-core + oz-rules
-- | This module runs both core whine rules and oz-specific rules
main :: Effect Unit
main = runWhineAndPrintResultsAndExit (WhineRules.rules <> OzRules.rules)
