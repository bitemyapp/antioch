Copyright (C) 2011 Associated Universities, Inc. Washington DC, USA.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

Correspondence concerning GBT software should be addressed as follows:
      GBT Operations
      National Radio Astronomy Observatory
      P. O. Box 2
      Green Bank, WV 24944-0002 USA


> module Antioch.Debug where

> import Antioch.DateTime
> import Antioch.Score
> import Antioch.Types
> import Antioch.Weather
> import Antioch.Utilities (rad2hrs)
> import Control.Monad.RWS.Strict
> import Data.Array
> import Data.Array.ST

This module contains methods to help the user better understand how sessions
were scored and how that scoring influenced the scheduling of the telescope.

Extract the debugging info that was relevant at a specific date and time.

> findTrace          :: DateTime -> [Trace] -> [Trace]
> findTrace dt trace =
>     case takeWhile (\(ts, _) -> ts <= dt) . byTimestamp $ trace of
>         []   -> []
>         prev -> let ((_, trace') : _) = reverse prev in trace'

Organize traces by date and time.

> byTimestamp :: [Trace] -> [(DateTime, [Trace])]
> byTimestamp (Timestamp dt : trace) = byTimestamp' dt trace
>   where
>     byTimestamp' dt trace = (dt, prev) : byTimestamp' dt' next
>       where
>         (prev, (Timestamp dt' : next)) = break isTimestamp trace

> getFreqPressureBinHistory, getFreqPressureHistory, getRaPressureHistory, getTimestampHistory, getCancellationHistory, getWindowPeriodsHistory :: [Trace] -> [Trace]
> getFreqPressureHistory    = filter isFreqPressureHistory
> getFreqPressureBinHistory = filter isFreqPressureBinHistory
> getRaPressureHistory      = filter isRaPressureHistory
> getTimestampHistory       = filter isTimestamp
> getCancellationHistory    = filter isCancellation
> getWindowPeriodsHistory   = filter isWindowPeriods

> isTimestamp (Timestamp _) = True
> isTimestamp _             = False

> isFreqPressureHistory (FreqPressureHistory _) = True
> isFreqPressureHistory _                       = False

> isFreqPressureBinHistory (FreqPressureBinHistory _) = True
> isFreqPressureBinHistory _                       = False

> isRaPressureHistory (RaPressureHistory _) = True
> isRaPressureHistory _                     = False

> isCancellation (Cancellation _) = True
> isCancellation _                = False

> isWindowPeriods :: Trace -> Bool
> isWindowPeriods (WindowPeriods _) = True
> isWindowPeriods _                 = False

> getCancellation :: Trace -> Period
> getCancellation (Cancellation period) = period

> getTimestamp :: Trace -> DateTime
> getTimestamp (Timestamp dt) = dt

> getFreqPressure :: Trace -> Array Band Float
> getFreqPressure (FreqPressureHistory fp) = fp

> getFreqPressureBin :: Trace -> Array Band (Int, Int)
> getFreqPressureBin (FreqPressureBinHistory fpb) = fpb

> getRaPressure :: Trace -> Array Int Float
> getRaPressure (RaPressureHistory rp) = rp

> getWindowPeriods (WindowPeriods wh) = wh
> getWindowPeriodsFromTrace :: [Trace] -> [(Window, Maybe Period, Period)]
> getWindowPeriodsFromTrace trace = whs
>   where
>     whs' = getWindowPeriodsHistory trace
>     whs  = [getWindowPeriods w | w <- whs']
> getCanceledPeriods :: [Trace] -> [Period]
> getCanceledPeriods trace = canceled
>   where
>     canceled' = getCancellationHistory trace
>     canceled  = [getCancellation c | c <- canceled']

Find the total amount of unused time in the schedule.

> deadTime periods = sum $ zipWith gapBetween periods (tail periods)
>   where
>     gapBetween p1 p2 = startTime p2 `diffMinutes` (duration p1 `addMinutes` startTime p1)

Find the total amount of time given to backup projects in the schedule.

> totalBackup periods = sum [duration p | p <- periods, pBackup p]

Find the total amount of scheduled periods that were cancelled due to bad weather.

> totalCancelled trace = sum [duration p | Cancellation p <- trace]
