module Whine.Bootstrap.WhineCoreMain where

import Whine.Runner.Prelude

import Whine.Core.WhineRules as WhineRules
import Whine.Runner (runWhineAndPrintResultsAndExit)

-- | Entry point for pre-bundled whine-core
-- | This module only runs the core whine rules without any bootstrap logic
main :: Effect Unit
main = runWhineAndPrintResultsAndExit WhineRules.rules
