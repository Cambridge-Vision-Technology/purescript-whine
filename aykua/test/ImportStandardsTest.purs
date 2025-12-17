module ImportStandardsTest where

-- ✅ CORRECT: Qualified import with matching alias
import Data.Maybe as Data.Maybe
import Data.Array as Data.Array
import Data.String as Data.String

-- ✅ CORRECT: Prelude is allowed without qualification
import Prelude

-- ✅ CORRECT: Symbol-only imports are allowed
import Type.Row (type (+))
import Data.Symbol (class IsSymbol)

-- ❌ VIOLATION: QualifiedImportsOnly - bare import without qualification
-- import Data.Map

-- ❌ VIOLATION: MatchingAliases - alias doesn't match module name
-- import Data.Either as E

-- ❌ VIOLATION: MatchingAliases - shortened alias
-- import Control.Monad.State as State

-- ❌ VIOLATION: NoDuplicateImports - duplicate import of same module
-- import Data.Maybe as Data.Maybe
-- import Data.Maybe as Data.Maybe

-- Test function demonstrating proper usage
testFunction :: Data.Maybe.Maybe String -> Array Int
testFunction maybeStr = case maybeStr of
  Data.Maybe.Nothing -> []
  Data.Maybe.Just s -> [ Data.String.length s ]
