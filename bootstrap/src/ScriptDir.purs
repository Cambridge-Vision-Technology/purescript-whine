module Whine.Bootstrap.ScriptDir where

import Effect (Effect)

foreign import getScriptDir :: Effect String
