module Whine.Bootstrap.WhineCoreMain where

import Whine.Runner.Prelude

import Aykua.WhineRules as AykuaRules
import Oz.WhineRules as OzRules
import Whine.Core.WhineRules as WhineRules
import Whine.Runner (runWhineAndPrintResultsAndExit)

-- | Entry point for pre-bundled whine-core + aykua + oz rules
-- | This module runs:
-- |   - whine-core: Base whine rules (UndesirableModules, UndesirableFunctions, etc.)
-- |   - aykua: Company-wide rules (QualifiedImportsOnly, UndesirableConsole, etc.)
-- |   - oz: Project-specific rules (UndesirableNdjson, UndesirableViewSend)
main :: Effect Unit
main = runWhineAndPrintResultsAndExit (WhineRules.rules <> AykuaRules.rules <> OzRules.rules)
