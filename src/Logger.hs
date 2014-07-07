{-# LANGUAGE Arrows #-}

module Main (main) where

-- import Control.Auto.Effects
-- import Control.Auto.Run
-- import Control.Monad.IO.Class
import Control.Auto hiding       (loop)
import Control.Auto.Blip
import Control.Auto.Serialize
import Control.Auto.Switch
import Control.Monad hiding      (forM_)
import Data.Foldable             (forM_)
import Data.Time
import Prelude hiding            (interact, id, (.), log)
import System.Locale

loggingFP :: FilePath
loggingFP = "data/save/logger"

main :: IO ()
main = do
    putStrLn "<< @history for history >>"
    putStrLn "<< @quit to quit >>"
    putStrLn "<< @clear to clear >>"

    -- loop through the 'loggerSwitch' wire, with implicit serialization
    loop $ serializing loggingFP loggerSwitch
  where
    loop a = do
      inp  <- getLine
      time <- getCurrentTime
      Output out a' <- stepAuto a (inp, time)
      forM_ out $ \str -> do
        putStrLn str
        loop a'



-- wrapper around 'logger'.  Basically, listenss for blips from 'logger'
-- and switches it out to a new blank log when it receives the blip.
loggerSwitch :: Monad m => Auto m (String, UTCTime) (Maybe String)
loggerSwitch = switchF (\() -> logger) logger

-- logger auto.  Takes in strings to log, or commands.  Outputs a 'Maybe
-- String', with 'Nothing' when it's "done"/quitting.  Also outputs
-- a 'Blip' that tells 'loggerSwitch' to swap out for a fresh logger auto.
logger :: Monad m
       => Auto m (String, UTCTime) (Maybe String, Blip ())
--               ^        ^         ^             ^
--               |        |         |             +-- tell 'switchF' in 'loggerSwitch' to switch to a new 'logger'
--               |        |         +-- Command line output.  Nothing means quit.
--               |        +-- Time of the command
--               +-- Command line input from 'interact'.
logger = proc (input, time) -> do
    let inputwords = words input

    case inputwords of
      -- mzero is Nothing, return is Just
      "@quit":_  -> do
        clear <- never -< ()
        id     -< (mzero, clear)

      "@clear":_ -> do
        clear <- now -< ()
        id     -< (return "Cleared!", clear)

      _          -> do

            -- is this a history request?
        let showHist = case inputwords of
                         "@history":_ -> True
                         _            -> False

            -- what to add to the log
            toLog | showHist  = ""
                  | otherwise = format time <> " "
                             <> input
                             <> "\n"

        -- accumulate the log
        log   <- mkAccum (++) "" -< toLog

        -- do not clear
        clear <- never -< ()

        -- output the history if requested, or just say "Logged" otherwise.
        let output | showHist  = displayLog log
                   | otherwise = "Logged."

        id     -< (return output, clear)

-- "pretty print" the log
displayLog :: String -> String
displayLog log = "Log length: " <> show loglength
              <> "\n--------\n"
              <> log
              <>   "--------\n"
              <> "Done."
  where
    loglength = length (lines log)

format :: UTCTime -> String
format = formatTime defaultTimeLocale "<%c>"