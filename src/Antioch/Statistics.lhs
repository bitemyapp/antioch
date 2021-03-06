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

> module Antioch.Statistics where

> import Antioch.DateTime   (fromGregorian, toGregorian, DateTime
>                          , addMinutes, diffMinutes, toSqlString
>                          , getCurrentTime)
> import Antioch.Generators
> import Antioch.Types
> import Antioch.Score
> import Antioch.Utilities  (hrs2rad, rad2hrs, rad2deg
>                          , utc2lstHours, dt2semester) 
> import Antioch.Weather
> import Antioch.TimeAccounting
> import Antioch.Debug
> import Antioch.ReceiverTemperatures
> import Control.Arrow      ((&&&), second)
> import Control.Monad      (filterM)
> import Data.Array
> import Data.Fixed         (div')
> import Data.Function      (on)
> import Data.List
> import Data.Time.Clock hiding (getCurrentTime)
> import Data.Maybe         -- (fromMaybe, isJust, fromJust)
> import Graphics.Gnuplot.Simple
> import System.Random      (getStdGen)
> import Test.QuickCheck    (generate, choose)
> --import System.CPUTime
> import Control.Monad.Writer
> import Control.Monad.RWS.Strict

> freqRange :: [Float]
> freqRange = [0.0..120.0] 

> raRange :: [Float]
> raRange = [0..24]

> decRange :: [Float]
> decRange = [-40..90]

> bandRange :: [Band]
> bandRange = [P .. W]

To Do List (port from Statistics.py):

   * used in error bars (used in plotObsEffVsFreq and plotMeanObsEffVsFreq)
      Stats done.  Still need to plot.
       * frequency mean
       * obs eff mean and standard deviation
   * historical bad fixed frequency and obs eff true (plotMeanObsEffVsFreq)
   * historical bad window frequency and obs eff true (plotMeanObsEffVsFreq)
   * true historical observing scores
   * historical pressure vs lst
      Need historical pressures

> compareWindowPeriodEfficiencies :: [(Window, Maybe Period, Period)] -> Weather -> ReceiverSchedule -> IO [((Period, Float), (Period, Float))]
> compareWindowPeriodEfficiencies winfo w rs = do
>     --w <- getWeather Nothing
>     dpsEffs <- historicalSchdMeanObsEffs dps w rs
>     cpsEffs <- historicalSchdMeanObsEffs cps w rs
>     return $ zip (zip cps cpsEffs) (zip dps dpsEffs)
>   where
>     dps = concat $ map (\(w, mc, d) -> if isJust mc then [d] else []) winfo 
>     cps = concat $ map (\(w, mc, d) -> if isJust mc then [fromJust mc] else []) winfo 
 
> calcMeanWindowEfficiencies :: [((Period, Float), (Period, Float))] -> (Float, Float)
> calcMeanWindowEfficiencies wps = (meanEff cpsEffs, meanEff dpsEffs)
>   where
>     cpsEffs = fst . unzip $ wps 
>     dpsEffs = snd . unzip $ wps 
>     meanEff psEffs = (sum $ map (\(p, e) -> (fromIntegral . duration $ p) * e) psEffs) / (sum $ map (fromIntegral . duration . fst) psEffs)

> fracObservedTimeByDays :: [Session] -> [Period] -> [(Float, Float)]
> fracObservedTimeByDays _  [] = []
> fracObservedTimeByDays [] _  = []
> fracObservedTimeByDays ss ps = map fracObservedTime days
>   where
>     days = [0 .. (numDays + 1)]
>     --numDays = ((diffMinutes lastDt firstDt) `div` (60 * 24)) 
>     --firstDt = startTime $ head ps
>     --lastDt  = startTime $ last ps
>     firstDt = fst $ getPeriodRange ps
>     numDays = snd $ getPeriodRange ps
>     total = totalSessionHrs ss
>     fracObservedTime day = (fromIntegral day,(total - (observed day)) / total)
>     observed day = getTotalHours $ observedPeriods day
>     observedPeriods day = takeWhile (\p -> startTime p < (toDt day)) ps
>     toDt day = (day * 24 * 60) `addMinutes` firstDt

> fracObservedTimeByDays' :: [Session] -> [Period] -> DateTime -> Int -> [(Float, Float)]
> fracObservedTimeByDays' _  [] _ _ = []
> fracObservedTimeByDays' [] _  _ _ = []
> fracObservedTimeByDays' ss ps start numDays = map fracObservedTime days
>   where
>     days = [0 .. (numDays + 1)]
>     --numDays = ((diffMinutes lastDt firstDt) `div` (60 * 24)) 
>     --firstDt = startTime $ head ps
>     --lastDt  = startTime $ last ps
>     total = totalSessionHrs ss
>     fracObservedTime day = (fromIntegral day,(total - (observed day)) / total)
>     observed day = getTotalHours $ observedPeriods day
>     observedPeriods day = takeWhile (\p -> startTime p < (toDt day)) ps
>     toDt day = (day * 24 * 60) `addMinutes` start

> getPeriodRange :: [Period] -> (DateTime, Int)
> getPeriodRange ps = (firstDt, numDays)
>   where
>     numDays = ((diffMinutes lastDt firstDt) `div` (60 * 24)) 
>     firstDt = startTime $ head ps
>     lastDt  = startTime $ last ps

> historicalSchdObsEffs ps = historicalSchdFactors ps observingEfficiency
> historicalSchdAtmEffs ps = historicalSchdFactors ps atmosphericEfficiency
> historicalSchdTrkEffs ps = historicalSchdFactors ps trackingEfficiency
> historicalSchdSrfEffs ps = historicalSchdFactors ps surfaceObservingEfficiency

> historicalSchdMeanObsEffs ps = historicalSchdMeanFactors ps observingEfficiency
> historicalSchdMeanAtmEffs ps = historicalSchdMeanFactors ps atmosphericEfficiency
> historicalSchdMeanTrkEffs ps = historicalSchdMeanFactors ps trackingEfficiency
> historicalSchdMeanSrfEffs ps = historicalSchdMeanFactors ps surfaceObservingEfficiency

> historicalObsMeanObsEffs ps = historicalObsMeanFactors ps observingEfficiency
> historicalObsMeanAtmEffs ps = historicalObsMeanFactors ps atmosphericEfficiency
> historicalObsMeanTrkEffs ps = historicalObsMeanFactors ps trackingEfficiency
> historicalObsMeanSrfEffs ps = historicalObsMeanFactors ps surfaceObservingEfficiency

For the given list of periods, return the concatanated list of results
for the given scoring factor that the periods' sessions had when they
were scheduled.  Currently this is used to check all the schedules scores
for normalicy (0 < score < 1).

> historicalSchdFactors :: [Period] -> ScoreFunc -> Weather -> ReceiverSchedule -> IO [Float]
> historicalSchdFactors ps sf w rs = do
>   --w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w rs) ps
>   return $ concat fs
>     where
>       periodSchdFactors' w rs p = periodSchdFactors p sf w rs

This function can be useful if invalid scores are encountered, and the 
offending period/session/project needs to be revealed.

> historicalSchdFactorsDebug :: [Period] -> ScoreFunc -> ReceiverSchedule -> IO [(Float,Period)]
> historicalSchdFactorsDebug ps sf rs = do
>   w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w rs) ps
>   return $ concat $ zipWith (\x y -> map (\y' -> (y', x)) y) ps fs --concat fs
>     where
>       periodSchdFactors' w rs p = periodSchdFactors p sf w rs

For the given list of periods, returns the mean of the scoring factor given
at the time that the periods' session was scheduled.  In other words, this
*almost* represents the exact scoring result for the periods' session at the
time the periods were scheduled.
Note: the use of mean' might cause misunderstandings, since pack zero's out
the first quarter.  We should be using the weighted average found in Score.

> historicalSchdMeanFactors :: [Period] -> ScoreFunc -> Weather -> ReceiverSchedule -> IO [Float]
> historicalSchdMeanFactors ps sf w rs = do
>   --w <- getWeather Nothing
>   fs <- mapM (periodSchdFactors' w rs) ps
>   return $ map mean' fs
>     where
>       periodSchdFactors' w rs p = periodSchdFactors p sf w rs

Same as historicalSchdMeanFactors, except calculates the efficiencies
that the period would have observed at.

> historicalObsMeanFactors :: [Period] -> ScoreFunc -> Weather -> ReceiverSchedule -> IO [Float]
> historicalObsMeanFactors ps sf w rs = do
>   --w <- getWeather Nothing
>   fs <- mapM (periodObsFactors' w rs) ps
>   return $ map mean' fs
>     where
>       periodObsFactors' w rs p = periodObsFactors p sf w rs

For the given period and scoring factor, returns the value of that scoring
factor at each quarter of the period *for the time it was scheduled*.
In other words, recreates the conditions for which this period was scheduled.

> periodSchdFactors :: Period -> ScoreFunc -> Weather -> ReceiverSchedule -> IO [Float]
> periodSchdFactors p sf w rs = do
>   rt <- getReceiverTemperatures
>   -- this step is key to ensure we use the right forecasts
>   w' <- newWeather w $ Just $ pForecast p
>   fs <- runScoring w' rs rt $ factorPeriod p sf  
>   return $ map eval fs

For the given period and scoring factor, returns the value of that scoring
factor at each quarter of the period *for the time it observed*.

> periodObsFactors :: Period -> ScoreFunc -> Weather -> ReceiverSchedule -> IO [Float]
> periodObsFactors p sf w rs = do
>   rt <- getReceiverTemperatures
>   fs <- mapM (periodObsFactors' p sf w rt rs) dts 
>   return $ map eval fs
>     where
>   dts = [(i*quarter) `addMinutes` (startTime p) | i <- [0..((duration p) `div` quarter)]]

> periodObsFactors' :: Period -> ScoreFunc -> Weather -> ReceiverTemperatures -> ReceiverSchedule -> DateTime -> IO Factors
> periodObsFactors' p sf w rt rs dt = do
>   -- this ensures we'll use the best forecasts and gbt_weather
>   w' <- newWeather w $ Just dt   
>   runScoring w' rs rt $ sf dt (session p) 

> sessionDecFreq :: [Session] -> [(Float, Radians)]
> sessionDecFreq = dec `vs` frequency

> periodDecFreq :: [Period] -> [(Float, Radians)]
> periodDecFreq = promote sessionDecFreq

> sessionDecRA :: [Session] -> [(Radians, Radians)]
> sessionDecRA = dec `vs` ra

> periodDecRA :: [Period] -> [(Radians, Radians)]
> periodDecRA = promote sessionDecRA

> sessionRA :: [Session] -> [(Radians, Float)]
> sessionRA = count (rad2hrs . ra) raRange

> periodRA :: [Period] -> [(Radians, Float)]
> periodRA = promote sessionRA

> sessionRAHrs :: [Session] -> [(Radians, Float)]
> sessionRAHrs =  histogram raRange . ((fractionalHours . sAllottedT) `vs` (rad2hrs . ra))

> periodRAHrs :: [Period] -> [(Radians, Float)]
> periodRAHrs = histogram raRange . ((fractionalHours . duration) `vs` (rad2hrs . ra . session))

> fractionalHours min = fromIntegral min / 60.0

> sessionDec :: [Session] -> [(Radians, Float)]
> sessionDec = count (rad2deg . dec) decRange --[-40..90]

> periodDec :: [Period] -> [(Radians, Float)]
> periodDec = promote sessionDec

> sessionDecHrs :: [Session] -> [(Radians, Float)]
> sessionDecHrs =  histogram decRange . ((fractionalHours . sAllottedT) `vs` (rad2deg . dec))

> periodDecHrs :: [Period] -> [(Float, Float)]
> periodDecHrs = histogram decRange . ((fractionalHours . duration) `vs` (rad2deg . dec . session)) 

> sessionFreq :: [Session] -> [(Float, Minutes)]
> --sessionFreq = histogram [1.0..50.0] . (sAllottedT `vs` frequency)
> sessionFreq = histogram freqRange . (sAllottedT `vs` frequency)

> sessionFreqHrs :: [Session] -> [(Float, Float)]
> sessionFreqHrs = histogramToHours . sessionFreq

> --statsFreqMinMax = (realToFrac . minimum $ statsFreqRange, realToFrac . maximum $ statsFreqRange)

> periodFreq :: [Period] -> [(Float, Minutes)]
> periodFreq =
>     histogram freqRange . (duration `vs` (frequency . session))

> periodFreqHrs :: [Period] -> [(Float, Float)]
> periodFreqHrs = histogramToHours . periodFreq

> periodFreqBackupHrs :: [Period] -> [(Float, Float)]
> periodFreqBackupHrs = histogramToHours . periodFreq . filter pBackup

Produces a histogram of the ratio of the canceled to scheduled hours by 
a special frequency bin.  Note that the periods passed in are what
was observed, so the original schedule is the join of the non-backup observed
periods with those that were canceled.

> periodCanceledFreqRatio :: [Period] -> [Trace] ->  [(Float, Float)]
> periodCanceledFreqRatio ps trace = zipWith3 canceledRatio freqBinMidpoints (canceledFreqHrs trace frequencyBins) (scheduledFreqHrs ps trace frequencyBins)
>   where
>     canceledRatio midPoint (_, canceled) (_, 0.0)       = (midPoint, 0.0)
>     canceledRatio midPoint (_, canceled) (_, scheduled) = (midPoint, canceled / scheduled)

> freqBinMidpoints :: [Float]
> freqBinMidpoints = midPoints (0.0 : frequencyBins)

> midPoints    :: [Float] -> [Float]
> midPoints xs = [(x1 + x2) / 2.0 | (x1 : x2 : _) <- tails xs]

> scheduledFreqHrs :: [Period] -> [Trace] -> [Float] -> [(Float, Float)]
> scheduledFreqHrs ps trace bins = histogram bins . ((fractionalHours . duration) `vs` (frequency . session)) $ getScheduledPeriods ps trace 

> getScheduledPeriods :: [Period] -> [Trace] -> [Period]
> getScheduledPeriods observed trace = observed' ++ canceled
>   where
>     canceled  = getCanceledPeriods trace
>     observed' = [p | p <- observed, not . pBackup $ p]

> canceledFreqHrs :: [Trace] -> [Float] -> [(Float, Float)]
> canceledFreqHrs trace bins = histogram bins . ((fractionalHours . duration) `vs` (frequency . session)) . getCanceledPeriods $ trace

> periodBackupFreqRatio :: [Period] -> [(Float, Float)]
> periodBackupFreqRatio ps = zipWith backupRatio (periodFreqHrsBinned ps) (periodFreqHrsBinned psBackups)
>   where
>     psBackups =  [p | p <- ps, pBackup p]
>     backupRatio obs backup = (fst obs, snd backup / snd obs)

> periodFreqHrsBinned :: [Period] -> [(Float, Float)]
> periodFreqHrsBinned = histogram frequencyBins . ((fractionalHours . duration) `vs` (frequency . session))

> histogramToHours :: [(Float, Minutes)] -> [(Float, Float)]
> histogramToHours =  map $ second fractionalHours

> sessionTP    :: [Period] -> [(Float, Int)]
> sessionTP ps = count f d ps
>   where
>     f = fractionalHours . duration
>     d = findDomain 1.0 . map f $ ps

Search the data to find an enumerable range bounding the input given a fixed step size.

> findDomain'      :: Real a => a -> [(a, b)] -> [a]
> findDomain' step = findDomain step . map fst

> findDomain         :: Real a => a -> [a] -> [a]
> findDomain step xs = [step * fromIntegral x | x <- [x1, x1+1 .. x2+1]]
>   where
>     [x1, x2] = map ((`div'` step) . ($ xs)) [minimum, maximum]

> sessionTPQtrs :: [Period] -> [(Minutes, Int)]
> sessionTPQtrs = count (duration) [0, quarter..(13*60)]


Counts how many sessions have a min duration for each quarter hour.
For randomly generated data, this should be a flat distribution.

> sessionMinDurationQtrs :: [Session] -> [(Minutes, Int)]
> sessionMinDurationQtrs = count (minDuration) [0, quarter..(13*60)]

> periodDuration :: [Period] -> [(Minutes, Minutes)]
> periodDuration = histogram [0, quarter..(13*60)] . (duration `vs` duration)

> periodStart :: DateTime -> [Period] -> [(Int, Int)]
> periodStart start = histogram [0..400] . (const 1 `vs` startDay)
>   where
>     startDay = flip div (24*60) . flip diffMinutes start . startTime

> sessionMinDuration :: [Session] -> [(Minutes, Minutes)]
> sessionMinDuration = histogram [0, quarter..(13*60)] . (minDuration `vs` minDuration)

What is the maximum amount of time that can be scheduled using the min duration.

> sessionMinDurMaxTime :: [Session] -> [(Minutes, Minutes)]
> sessionMinDurMaxTime = histogram [0, quarter..(13*60)] . (maxNumTPTime `vs` minDuration)
>   where
>     maxNumTPTime s = maxNumTPs s * minDuration s
>     maxNumTPs s = sAllottedT s `div` minDuration s

Example of scatter plot data w/ datetime:

> freqTime :: [Period] -> [(DateTime, Float)]
> freqTime = (frequency . session) `vs` startTime

Example of log histogram data:
Compare allocated hours by frequency to observed hours by frequency.

> periodBand :: [Period] -> [(Band, Float)]
> periodBand = histogram bandRange . ((fractionalHours . duration) `vs` (band . session))

> sessionBand :: [Session] -> [(Band, Float)]
> sessionBand = histogram bandRange . ((fractionalHours . sAllottedT) `vs` band)

> sessionAvBand :: [Session] -> [(Band, Float)]
> sessionAvBand = histogram bandRange . ((fractionalHours . availableTime) `vs` band)

What is the number of sessions in each band that are closed?

> sessionClosedBand :: [Session] -> [(Band, Float)]
> sessionClosedBand ss = histogram bandRange $ closedVsBand ss -- . ((fractionalHours . sAllottedT) `vs` band)
>   where
>     closedVsBand ss = map (\(b, t) -> if t then (b,1.0::Float) else (b,0.0::Float)) $ sClosed `vs` band $ ss

> periodEfficiencyByBand :: [Period] -> [Float] -> [(Band, Float)]
> periodEfficiencyByBand ps es = 
>     histogram bandRange . (effSchdMins `vs` (band . session . fst)) $ zip ps es
>   where 
>     effSchdMins (p, e) = e * (fractionalHours . duration $ p)

> decVsElevation :: [Period] -> [(Float, Radians)]
> decVsElevation ps = (dec . session) `vs` elevationFromZenith $ ps 

> --etaFn :: [(Frequency, Float)]
> --etaFn = [(f, minObservingEff f) | f <- [2.0 .. 60.0]]

> efficiencyVsFrequency :: [Session] -> [Float] -> [(Float, Float)]
> efficiencyVsFrequency sessions =
>     (snd `vs` (frequency . fst)) . zip sessions

> historicalFreq :: [Period] -> [Float]
> historicalFreq = map (frequency . session)

> historicalDec :: [Period] -> [Radians]
> historicalDec = map (dec . session)

> historicalRA :: [Period] -> [Radians]
> historicalRA = map (ra . session)

> historicalTime :: [Period] -> [DateTime]
> historicalTime = map startTime
>
> historicalTime' :: [Period] -> [Int]
> historicalTime' ps = map (minutesToDays . flip diffMinutes tzero) times
>   where
>     times = sort . map startTime $ ps
>     tzero = head times

> historicalTime'From :: DateTime -> [Period] -> [Int]
> historicalTime'From tzero ps = map (minutesToDays . flip diffMinutes tzero) times
>   where
>     times = sort . map startTime $ ps

> minutesToDays  min = min `div` (24 * 60)
> fractionalDays min = fromIntegral min / (24.0 * 60.0)

> historicalExactTime' :: [Period] -> Maybe DateTime -> [Float]
> historicalExactTime' ps start = map (fractionalDays . flip diffMinutes tzero) times
>   where
>     times = sort . map startTime $ ps
>     tzero = fromMaybe (head times) start

> historicalTime'' :: [DateTime] -> [Int]
> historicalTime'' dts = map (minutesToDays . flip diffMinutes tzero) times
>   where
>     times = sort dts 
>     tzero = head times

> historicalExactTime'' :: [DateTime] -> Maybe DateTime -> [Float]
> historicalExactTime'' dts start = map (fractionalDays . flip diffMinutes tzero) times
>   where
>     times = sort dts 
>     tzero = fromMaybe (head times) start

> historicalLST    :: [Period] -> [Float]
> historicalLST ps = [utc2lstHours . addMinutes (duration p `div` 2) . startTime $ p | p <- ps]

Produces a tuple of (satisfaction ratio, sigma) for each frequency bin scheduled.

> killBad n | isNaN n      = 0.0 -- Is this is right value to return?
>           | isInfinite n = 1.0 -- Is this is right value to return?
>           | otherwise    = n

> satisfactionRatio :: [Session] -> [Period] -> [(Float, Float, Float)]
> --satisfactionRatio ss ps = zip3 [1.0..50.0] sRatios sigmas
> satisfactionRatio ss ps = zip3 freqs sRatios sigmas
>   where 
>     pMinutes   = map (fromIntegral . snd) (periodFreq ps) 
>     sMinutes   = map (fromIntegral . snd) (sessionFreq ss)
>     totalRatio = ratio pMinutes sMinutes
>     sRatios    = [killBad (x / y / totalRatio) | (x, y) <- zip pMinutes sMinutes]
>     sigmas     = [killBad (sqrt (x / y)) | (x, y) <- zip sRatios sMinutes]
>     freqs      = freqRange

> totalHrs      :: [Session] -> (Session -> Bool) -> Float
> totalHrs ss f = fractionalHours . sum $ [sAllottedT s | s <- ss, f s]

> totalPeriodHrs      :: [Period] -> (Period -> Bool) -> Float
> totalPeriodHrs ps f = fractionalHours . sum $ [duration p | p <- ps, f p]

> isInSemester :: Session -> String -> Bool
> isInSemester s sem = (semester . project $ s) == sem

> isPeriodInSemester :: Period -> String -> Bool
> isPeriodInSemester p sem = (dt2semester . startTime $ p) == sem

> isPeriodFromSemester :: Period -> String -> Bool
> isPeriodFromSemester p sem = (semester . project . session $ p) == sem

Daily average of the atmospheric, tracking, surface, and
observing efficiencies across all sessions
by band and across all hours of the day within HA limits.

> bandEfficiencyByTime :: Weather -> [Session] -> DateTime -> Int -> IO [[(Score, Score, Score, Score)]]
> bandEfficiencyByTime w ss day dur = do
>   res <- mapM (bandEfficiencyByTime' w ss) days
>   return $ transpose res
>     where
>       days = [                               day
>             ,  ((1*24*60)       `addMinutes` day)
>             .. (((dur-1)*24*60) `addMinutes` day)
>              ]

Average of the atmospheric, tracking, surface, and
observing efficiencies across all sessions
by band and across all hours of the day within HA limits.

> bandEfficiencyByTime' :: Weather -> [Session] -> DateTime -> IO [(Score, Score, Score, Score)]
> bandEfficiencyByTime' w ss day = do
>   print $ (toSqlString day)
>   begin <- getCurrentTime
>   -- avoid getting real gbt_weather by setting forecast behind time
>   let wdt = ((-60) `addMinutes` day)
>   w' <- newWeather w $ Just wdt 
>   rt <- getReceiverTemperatures
>   efs <- mapM (bandEfficiencyByBand w' rt day ss hrs) bandRange
>   --return $! map means . map unzip4 . map (map extract . filter haTest) $ efs
>   let result = map means . map unzip4 . map (map extract . filter haTest) $ efs
>   print result  -- makes unit tests look like they are failing
>   end <- getCurrentTime
>   let execTime = end - begin
>   print $ "execution time: " ++ (show execTime)
>   return $! result
>     where
>       hrs = [                     day
>            , (1*60)  `addMinutes` day
>           .. (23*60) `addMinutes` day]
>       extract [(_, Just a), (_, Just t), (_, Just u), _] = (a, t, u, a*t*u)
>       haTest [_, _, _, (_, jha)] = maybe False (==1.0) jha
>       means (as, ts, us, os) = (sum as / n, sum ts / n, sum us / n, sum os / n)
>         where
>           n = fromIntegral . length $ as

> bandEfficiencyByBand :: Weather -> ReceiverTemperatures -> DateTime -> [Session] -> [DateTime] -> Band -> IO [Factors]
> bandEfficiencyByBand w rt dt ss hrs b = do
>   mapM (\(dt, s) -> getEfficiencyFactors w rt [] dt s) dtss
>     where
>       isBand bandName s = band s == bandName
>       ss' = filter (isBand b) ss
>       dtss = [(dt, s) | dt <- hrs, s <- ss']

> inHourAngleLimit :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> DateTime -> Session -> IO Bool
> inHourAngleLimit w rt rs dt s = do 
>     result <- runScoring w rs rt (hourAngleLimit dt s)
>     return $ 1.0 == eval result

> getEfficiencyFactors :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> DateTime -> Session -> IO Factors
> getEfficiencyFactors w rt rs dt s  = do
>   ef <- runScoring w [] rt $ getEfficiencyScoringFactors w rt rs dt s
>   return ef

> getEfficiencyScoringFactors :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> DateTime -> Session -> Scoring Factors
> getEfficiencyScoringFactors w rt rs dt s = do 
>     effs <- calcEfficiency dt s
>     let effFactors =       [(atmosphericEfficiency' . fmap fst) effs
>                           , trackingEfficiency
>                           , surfaceObservingEfficiency
>                           , (hourAngleLimit' . fmap snd) effs
>                            ]
>     score effFactors dt s

The next few methods are for calculating the efficiencies (both
observed & scheduled) of periods.

PeriodEfficiency is (period
                   , [(atmosphericEfficiency
                     , trackingEfficiency
                     , surfaceObservingEfficiency
                     , observingEfficiency)])

> type PeriodEfficiency   = (Period, [(Score, Score, Score, Score)])
> type PeriodEfficiencies = [PeriodEfficiency]

Note that the first argument is [WindowPeriods], i.e., it comes from calling
getWindowPeriodsFromTrace on the Trace

> partitionWindowedPeriodEfficiencies :: [(Window, Maybe Period, Period)] ->
>                                        PeriodEfficiencies ->
>                                        (PeriodEfficiencies, PeriodEfficiencies)
> partitionWindowedPeriodEfficiencies wps pes = partition isAChosen pes
>   where
>     chosen = catMaybes . map second $ wps
>     second (a, b, c) = b
>     isAChosen pe = elem (fst pe) chosen

Same as original method, but we don't need the hourAngleLimit.

> getEfficiencyScoringFactors' :: DateTime -> Session -> Scoring Factors
> getEfficiencyScoringFactors' dt s = do 
>     let effFactors =  [atmosphericEfficiency 
>                      , trackingEfficiency
>                      , surfaceObservingEfficiency
>                       ]
>     score effFactors dt s

Get efficiency factors for every quarter of the period but the overhead.

> getPeriodEffFactors' :: Period -> Scoring [Factors]
> getPeriodEffFactors' p = do
>     fs <- mapM (getEfficiencyScoringFactors'' s) dts
>     return fs
>   where
>     s = session p
>     dt = startTime p
>     dur = duration p
>     getEfficiencyScoringFactors'' s dt = getEfficiencyScoringFactors' dt s
>     dts = drop (getOverhead s) $ [(15 * m) `addMinutes` dt | m <- [0 .. (dur `div` 15) - 1]]

Get efficiency factors for every quarter of the period but the overhead, but making sure that we evaluate the period the same way
in which it's MOC was evaluated during simulations.
What we're trying to do here is reproduce details so we can 
understand why a period was canceled.

> getCanceledPeriodEffFactors :: Period -> Scoring [Factors]
> getCanceledPeriodEffFactors p = do 
>   -- reset the weather origin to one hour before the period
>   w <- weather
>   let wDt = addMinutes (-60) (startTime p) -- 1 hr before period starts
>   w' <- liftIO $ newWeather w (Just wDt)
>   -- make sure all subsequent calls use this weather
>   local (\env -> env { envWeather = w' }) $ getPeriodEffFactors' p


For the given period, get the *observed* efficiencies at each quarter in
the periods duration.  We can only do this by restting the weather for
each quarter so that we pick up gbt_weather and latest forecast.

> getPeriodObsEffFactors :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> Period -> IO [Factors]
> getPeriodObsEffFactors w rt rs p = do
>     -- to get the observed efficiencies, we need to use the gbt weather
>     -- where we can, and the best forecast where we can't.
>     -- a simple way of doing this is to simply set the origin of the 
>     -- weather to be the end point of the period - since all times
>     -- will now be in the 'past'.
>     w' <- newWeather w $ Just $ periodEndTime p
>     mapM (getObsEffScoringFactors w' rt rs (session p)) dts
>   where
>     dts = [(startTime p)
>         ,  (addMinutes 15 (startTime p))
>         .. (addMinutes (duration p) (startTime p))]
>     getObsEffScoringFactors w rt rs s dt = runScoring w rs rt $ getEfficiencyScoringFactors' dt s


> getPeriodSchdEffFactors :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> Period -> IO [Factors]
> getPeriodSchdEffFactors w rt rs p = do
>   -- here's how we get the efficiencies at the time this period was sched
>   w' <- newWeather w $ Just (pForecast p)
>   runScoring w' rs rt $ mapM (flip getEfficiencyScoringFactors' (session p)) dts
>   where
>     dts = [(startTime p)
>         ,  (addMinutes 15 (startTime p))
>         .. (addMinutes (duration p) (startTime p))]

> getPeriodsObsEffs :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> [Period] -> IO (PeriodEfficiencies) 
> getPeriodsObsEffs w rt rs ps = do
>   effs <- mapM (getPeriodObsEffFactors w rt rs) ps
>   return $ zip ps (map fs2ss effs)
>     where
>       fs2ss ss = map f2s ss

For each period, first reproduce the 3 efficiencies that helped
determine why the period was canceled, then also calculate
the product of the three (observing efficiency factor).

> getCanceledPeriodsEffs :: [Period] -> Scoring (PeriodEfficiencies) 
> getCanceledPeriodsEffs ps = do
>   effs <- mapM getCanceledPeriodEffFactors ps
>   return $ zip ps (map fs2ss effs)
>     where
>       fs2ss ss = map f2s ss

Same as getPeriodsObsEffs, but here we want the periods effs at the time of scheduling.

> getPeriodsSchdEffs :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> [Period] -> IO (PeriodEfficiencies) 
> getPeriodsSchdEffs w rt rs ps = do
>   effs <- mapM (getPeriodSchdEffFactors w rt rs) ps
>   return $ zip ps (map fs2ss effs)
>     where
>       fs2ss ss = map f2s ss

For a single period's [Factors], convert them to scores for each timestamp.
Take the three efficiency factors, extract the scores, and calculate
the observing efficiency.
[("AtmosphericEfficiency", Just 1.0) , ("TrackingEfficiency", Just 1.0, ..]
  -> (1.0, 1.0, 1.0, 1.0)

> f2s :: [(String, Maybe Score)] -> (Score, Score, Score, Score)
> f2s fs = (at, tr, sf, ef)
>   where
>     at = eval [fs!!0] 
>     tr = eval [fs!!1] 
>     sf = eval [fs!!2] 
>     ef = eval fs

Convert the period efficiencies that are given, into the data we 
want to plot.

> extractPeriodMeanEffs :: PeriodEfficiencies -> ((Score, Score, Score, Score) -> Score) -> [Score]
> extractPeriodMeanEffs peffs fn = map (avg . snd) peffs
>   where
>     avg xs = avg' $ map fn xs
>     avg' xs = (sum xs)/(fromIntegral . length $ xs)

For Canceled Periods, we'll want to reproduce values that determined

wether the period was canceled or not, so we'll want:
   * the period
   * the adjusted min obs value (minObs in minimumObservingConditions)
   * the mean efficiency product (meanEff in min.Obs.Conditions)
   * for each quarter:
       * the 4 observed efficiencies 
       * the tracking error limit 
       * the gbt_wind 

> type CanceledPeriodDetail  = (Period,Float,Float,[(Score, Score, Score, Score)], [Maybe Score], [Maybe Float])
> type CanceledPeriodDetails = [CanceledPeriodDetail]  

> getCanceledPeriodsDetails :: Weather -> ReceiverTemperatures -> ReceiverSchedule -> [Period] -> IO (CanceledPeriodDetails)
> getCanceledPeriodsDetails w rt rs ps = do
>   -- get the effs for each period
>   peffs <- runScoring w rs rt $ getCanceledPeriodsEffs ps 
>   -- get all the other crap
>   crap <- mapM (getCanceledPeriodCrap w rt rs) ps
>   let minobs = map adjMinObs ps
>   return $ zipWith3 mkDetails peffs crap minobs 
>     where
>   adjMinObs p = adjustedMinObservingEff $ minObservingEff . frequency . session $ p
>   mkDetails (p, effs) (trls, w2s, meanEff) mo = (p, mo, meanEff, effs, trls, w2s)

This gets the the left over crap not covered by getPeriodsObsEffs:
   * tracking error limits
   * gbt wind speeds
   * the mean efficiency (that gets compared to min. obs. in
     minimumObservingConditions).

> getCanceledPeriodCrap ::  Weather -> ReceiverTemperatures -> ReceiverSchedule -> Period -> IO ([Maybe Score], [Maybe Float], Float) 
> getCanceledPeriodCrap w rt rs p = do
>   w' <- newWeather w $ Just dt
>   -- gbt_wind
>   w2winds <- mapM (gbt_wind w') dts
>   -- tracking error limits
>   trkErrLmts <- mapM (trk w' rs rt s) dts
>   -- the mean efficiency, as calculated in minimumObservingConditions
>   fcts <- mapM (minObsFactors' w rs rt s (startTime p)) dts
>   let effProducts = map (\(fs, tr) -> ((eval fs) * tr)) fcts
>   let meanEff = (sum effProducts) / (fromIntegral . length $ effProducts)
>   return (trkErrLmts, w2winds, meanEff)
>     where
>   s  = session p
>   dt = startTime p
>   dur = duration p
>   dts = drop (getOverhead s) $ [(15 * m) `addMinutes` dt | m <- [0 .. (dur `div` 15) - 1]]
>   trk w rs rt s dt = do
>       [(_, trkErrLmt)] <- runScoring w rs rt $ trackingErrorLimit dt s
>       return trkErrLmt

These are wrappers to the minObsFactors function in Score.lhs:
we need the wrappers to make sure that the function is evaluated
in the same way as minimumObservingConditions was during simulations.
The intent here is to produce reports that let us know *why*
a period was canceled.

> minObsFactors' :: Weather -> ReceiverSchedule -> ReceiverTemperatures -> Session -> DateTime -> DateTime -> IO (Factors, Float)
> minObsFactors' w rs rt s start dt = runScoring w rs rt $ minObsFactors'' s start dt

> minObsFactors'' :: Session -> DateTime -> DateTime -> Scoring (Factors, Float)
> minObsFactors'' s start dt = do
>   -- reset the weather origin to one hour before the period
>   w <- weather
>   let wDt = addMinutes (-60) start -- 1 hr before period starts
>   w' <- liftIO $ newWeather w (Just wDt)
>   -- make sure all subsequent calls use this weather
>   local (\env -> env { envWeather = w' }) $ minObsFactors s dt 


This function retrieves the history of pressures written in the trace, 
and returns them, for each band as [(day #, pressure)].

> bandPressuresByTime :: [Trace] -> [[(Float, Float)]]
> bandPressuresByTime trace = --[zip (replicate 3 1.0) (replicate 3 2.0)]
>     map bandData bandRange 
>   where
>     bandData band = [(fromIntegral x, y) | (x, y) <- zip days (getBandData band)]
>     fp    = getFreqPressureHistory trace -- [(array (L,W) [(L,9.850087), ..]]
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getBandData band = getBandPressures band fp
>     

> getBandPressures :: Band -> [Trace] -> [Float]
> getBandPressures band bp = map (getBandPressure band) bp 
>   where
>     getBandPressure band t = getFreqPressure t ! band

This function retrieves the history of pressure bins written in the trace, 
and returns them, for each band as [(day #, (n, d))].
Here n and d are used for calculating the pressure: 1 + log (n/d)
We sometimes refer to n as 'remaining' and d as 'past'.

> bandPressureBinsByTime :: [Trace] -> [[(Float, (Int, Int))]]
> bandPressureBinsByTime trace = --[zip (replicate 3 1.0) (replicate 3 2.0)]
>     map bandData bandRange
>   where
>     bandData band = [(fromIntegral x, y) | (x, y) <- zip days (getBandData band)]
>     fp    = getFreqPressureBinHistory trace -- [(array (L,W) [(L,9.850087), ..]]
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getBandData band = getBandPressureBins band fp
>     

> getBandPressureBins :: Band -> [Trace] -> [(Int, Int)]
> getBandPressureBins band bp = map (getBandPressureBin band) bp 
>   where
>     getBandPressureBin band t = getFreqPressureBin t ! band

> raPressuresByTime :: [Trace] -> [[(Float, Float)]]
> raPressuresByTime trace = 
>     map (raData . round) raRange
>   where
>     raData ra = [(fromIntegral x, y) | (x, y) <- zip days (getRaData ra)]
>     rap   = getRaPressureHistory trace
>     times = getTimestampHistory trace
>     days  = historicalTime'' [getTimestamp t | t <- times]
>     getRaData ra = getRaPressures ra rap

> getRaPressures    :: Int -> [Trace] -> [Float]
> getRaPressures ra = map $ \t -> getRaPressure t ! ra

The originally scheduled periods can be reconstructed from the observed
periods, and those that were canceled: put every canceled period in its
original slot (this will be overwritting a backup period, or a blank).

> getOriginalSchedule :: [Period] -> [Trace] -> [Period]
> getOriginalSchedule observed trace = sort $ originals observed ++ canceled
>   where 
>     canceled = getCanceledPeriods trace
>     originals ps = [p | p <- ps, not . pBackup $ p]

> getOriginalSchedule' :: [Period] -> [Period] -> [Period]
> getOriginalSchedule' observed canceled = sort $ originals observed ++ canceled
>   where 
>     originals ps = [p | p <- ps, not . pBackup $ p]

> getScheduledDeadTime :: DateTime -> Minutes -> [Period] -> [Trace] -> [(DateTime, Minutes)]
> getScheduledDeadTime start dur observed = findScheduleGaps start dur . getOriginalSchedule observed

> getScheduledDeadTimeHrs :: DateTime -> Minutes -> [Period] -> [Trace] -> Float
> getScheduledDeadTimeHrs start dur obs = fractionalHours . sum . map (\dt -> snd dt) . getScheduledDeadTime start dur obs

> findScheduleGaps :: DateTime -> Minutes -> [Period] -> [(DateTime, Minutes)]
> findScheduleGaps start dur ps = findScheduleGaps' $
>     begin : [(startTime p, duration p) | p <- ps] ++ [end]
>   where
>     begin = (start, 0)
>     end   = (dur `addMinutes` start, 0)

> findScheduleGaps' ps = [(d1 `addMinutes` s1, gap) |
>     ((s1,d1), (s2,d2)) <- zip ps (tail ps), gap <- [(s2 `diffMinutes` s1) - d1], gap > 0]

> getTotalHours :: [Period] -> Float
> getTotalHours = fractionalHours . sum . map duration

> totalSessionHrs :: [Session] -> Float
> totalSessionHrs = fractionalHours . sum . map sAllottedT

If you were scheduling with the scheduleMinDuration strategy, how much
time could you really schedule with these sessions?

> totalSessMinDurHrs :: [Session] -> Float
> totalSessMinDurHrs = fractionalHours . sum . map availableTime

> availableTime s
>     | minDuration s == 0 = 0
>     | otherwise          = minDuration s * (sAllottedT s `div` minDuration s)

> crossCheckSimulationBreakdown :: Float -> Float -> Float -> Float -> Float -> Float -> Float -> Float -> String
> crossCheckSimulationBreakdown simulated scheduled observed canceled obsBackup totalDead schedDead failedBackup =
>     concat warnings ++ "\n"
>   where
>     error = "WARNING: "
>     w1 = if totalDead /= schedDead + failedBackup then error ++ "Total Dead Time != Scheduled Dead Time + Failed Backup Time!" else ""
>     -- this warning is no longer applicable, since each simulation stip
>     -- calls dailySchedule, which schedule's more then the 'simulated' time
>     w2 = "" -- if observed + totalDead /= simulated then error ++ "Total Simulated Time != Observed + Dead Times!\n" else ""
>     w3 = if scheduled - observed /= canceled - obsBackup then error ++ "Scheduled - Observed Time != Canceled - Observed Backup Times!\n" else ""
>     warnings = [w1, w2, w3]

> breakdownSimulationTimes :: [Session] -> DateTime -> Minutes -> [Period] -> [Period] -> (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float)
> breakdownSimulationTimes sessions start dur observed canceled = 
>     ( fractionalHours dur                            -- simHrs
>     , totalSessionHrs sessions                       -- sessHrs
>     , totalSessionHrs . filter backup $ sessions     -- sessBackupHrs
>     , totalSessMinDurHrs sessions                    -- sessAvHrs
>     , totalSessMinDurHrs . filter backup $ sessions  -- sessAvBackupHrs
>     , getTotalHours originalSchedule                 -- scheduledHrs
>     , getTotalHours observed                         -- observedHrs
>     , canceledHrs
>     , obsBackupHrs
>     , fractionalHours . sum $ map snd observedGaps   -- totalObsDeadHrs
>     , fractionalHours . sum $ map snd scheduledGaps  -- totalSchDeadHrs
>     , canceledHrs - obsBackupHrs                     -- failedBackupHrs
>     )
>   where
>     originalSchedule = getOriginalSchedule' observed canceled
>     canceledHrs      = getTotalHours canceled
>     obsBackupHrs     = getTotalHours . filter pBackup $ observed
>     observedGaps     = findScheduleGaps start dur observed
>     scheduledGaps    = findScheduleGaps start dur originalSchedule

> scheduleHonorsFixed :: [Period] -> [Period] -> Bool
> scheduleHonorsFixed [] _ = True
> scheduleHonorsFixed fixed schedule =  dropWhile (==True) (findFixed fixed schedule) == []
>   where
>     findFixed fs schedule = [isJust (find (==f) schedule) | f <- fs]

Read Y versus X as you would expect with normal plotting nomenclature.
Produces list of (x, y) coordinate pairs.

> vs       :: (a -> b) -> (a -> c) -> [a] -> [(c, b)]
> y `vs` x = map $ x &&& y

> count :: (Ord a, Ord b, Num b) => (t -> a) -> [a] -> [t] -> [(a, b)]
> count f buckets = histogram buckets . (const 1 `vs` f)

> histogram :: (Ord a, Ord b, Num b) => [a] -> [(a, b)] -> [(a, b)]
> histogram buckets xys = [(x, sum ys) | (x, ys) <- allocate buckets xys]

> allocate buckets = allocate' buckets . sort
          
> allocate'            :: (Ord a, Ord b, Num b) => [a] -> [(a, b)] -> [(a, [b])]
> allocate' []     _   = []
> allocate' (b:bs) xys = (b, map snd within) : allocate' bs without
>   where
>     (within, without) = span (\(x, _) -> x <= b) xys

> meanFreqsByBin       :: [Float] -> [Float]
> meanFreqsByBin freqs = mean frequencyBins [(x, x) | x <- freqs]

> medianByBin :: [(Float, Float)] -> [Float]
> medianByBin  = median frequencyBins

> meanByBin :: [(Float, Float)] -> [Float]
> meanByBin  = mean frequencyBins

> stddevByBin :: [(Float, Float)] -> [Float]
> stddevByBin  = stddev frequencyBins

> sdomByBin :: [(Float, Float)] -> [Float]
> sdomByBin  = sdom frequencyBins


> mean, median, stddev, sdom   :: [Float] -> [(Float, Float)] -> [Float]
> [mean, median, stddev, sdom] = map simpleStat [mean', median', stddev', sdom']

simpleStat provides a way to perform statistics on binned data

> simpleStat f buckets = map (f . snd) . allocate buckets

histStat provides a way to perform statistics on histogram data
f is a function like mean', etc.

> histStat :: ([Float] -> Float) -> [(Float, Float)] -> Float
> histStat f histData = f newData
>   where
>     newData = concat $ map (\x -> replicate (round . snd $ x) (fst x)) histData

> mean' xs = sum xs / (fromIntegral . length $ xs)

> median' xs = sort xs !! (length xs `div` 2)

> stddev' xs = sqrt $ sum [(x - m) ^ 2 | x <- xs] / (fromIntegral . length $ xs)
>   where
>     m = mean' xs

> sdom' xs = stddev' xs / (sqrt . fromIntegral . length $ xs)

> ratio :: [Float] -> [Float] -> Float
> ratio = (/) `on` sum

> frequencyBins :: [Float]
> frequencyBins =
>     [0.0, 2.0, 3.95, 5.85, 10.0, 15.4, 20.0, 24.0, 26.0, 30.0, 35.0, 40.0, 45.0, 50.0, 80.0, 85.0, 90.0, 95.0, 100.0, 105.0, 110.0, 115.0, 120.0]

> promote   :: ([Session] -> t) -> [Period] -> t
> promote f = f . map session
